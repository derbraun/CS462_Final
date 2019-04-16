ruleset store {
  meta {
    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.wrangler alias Wrangler
    use module key_module
    use module twilio alias twilio
      with account_sid = keys:twilio{"account_sid"}
        auth_token = keys:twilio{"auth_token"}
    
    shares __testing, getProfile, getOrders
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" },
        { "name": "getProfile" },
        { "name": "getOrders" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      { "domain": "store", "type": "update_profile", "attrs": ["min_driver_rank", "auto_assign_driver"]},
      { "domain": "store", "type": "update_pulse", "attrs": ["pulse"]},
      { "domain": "utility", "type": "update_location", "attrs": ["lat", "long"]}
      ]
    }
    
    notification_from_phone_number = 12108800482
    
    // Testing Functions *******************************************************
    getProfile = function(){ent:profile}
    getOrders = function(){ent:order_tracker}
    // *************************************************************************
    
    makeRequest = function(order){
      {"request": {
          "orderId": order{"orderId"},
          "pickUpTime": time:now(),
          "requiredDeliveryTime": time:add(order{"ordered_at"},{"hours": 2}),
          "sendBidTo": Wrangler:myself(){"eci"},
          "storeLocation": ent:profile{"storeLocation"},
          "maxDistance": ent:profile{"maxDistance"}
        }
      }
    }
    
    getLowestBid = function(order){
      bids = order{"bids"};
      bids.length() > 0 => 
        bids.reduce(function(f,s){f{["bid","bidAmount"]} < s{["bid","bidAmount"]} => f | s })
        | null;
    }
  }
  
  // Utility rules *************************************************************
  rule initialize {
    select when wrangler ruleset_added where rids >< meta:rid
  
    always {
      ent:order_tracker := {};
      ent:profile := {"min_driver_rank": 50, 
                      "auto_assign_driver": true,
                      "accept_bids_wait_time": 10, // in seconds
                      "storeLocation":{"lat": 40.251887, "long": -111.649332}};
      // ent:bid_channel := Wrangler:createChannel(null, "bid_channel", "bid_channel", null)
      
      raise utility event "pulse" attributes {"nothing":"nothing"} // have no atributes crashes here sometimes
    }    
  }
  
  rule scheduler {
    select when utility pulse
    always {
      schedule utility event "pulse" 
        at time:add(time:now(), {"seconds":  ent:profile{"accept_bids_wait_time"}}) // probably change this to minutes in a real world scenario
    }
  }
  
  rule update_profile {
    select when store update_profile
    
    pre {
      min_driver_rank = event:attrs{"min_driver_rank"}.decode();
      auto_assign_driver = event:attrs{"auto_assign_driver"}.decode();
    }
    
    always {
      ent:profile{"min_driver_rank"} := min_driver_rank.isnull() => ent:profile{"min_driver_rank"} | min_driver_rank;
      ent:profile{"auto_assign_driver"} := auto_assign_driver.isnull() => ent:profile{"auto_assign_driver"} | auto_assign_driver;
    }
  }
  
  rule update_pulse {
    select when store update_pulse
    always{
      ent:profile{"accept_bids_wait_time"} := event:attrs{"pulse"}.decode();
    }
  }
  
  rule update_location {
    select when utility update_location
    always {
      ent:profile{["storeLocation", "lat"]} := event:attrs{"lat"};
      ent:profile{["storeLocation", "long"]} := event:attrs{"long"};
    }
  }
  // ***************************************************************************
  
  // Logic rules ***************************************************************
  rule auto_assign_driver {
    select when utility pulse where ent:profile{"auto_assign_driver"}
    foreach ent:order_tracker.filter(function(v,k){v{"assigned_driver"}.isnull()}) setting (order) // get orders without an assigned_driver
    pre {
      selected_bid = getLowestBid(order);
    }
    
    if selected_bid then
        event:send({"eci": selected_bid{["bid", "driver_channel"]}, 
                  "domain":"driver", "type":"assigned_delivery", 
                  "attrs":{"orderId": order{["details","orderId"]}}});
    
    fired {
      // update order_tracker
      ent:order_tracker{[order{["details", "orderId"]}, "assigned_driver"]} := selected_bid{["bid", "driver_channel"]};
      
      // send twilio message
      raise utility event "notify_customer" attributes {"to": order{["details", "customer_phone"]}}
    }
  }
  
  // This rule uses a fake client to demonstraite a store that doesn't use auto-assign.
  //  If there was a client for store owners to view and select bids, this rule 
  //  would send them the bids.
  //  This will send bids every ent:check_interval
  rule send_bids_to_client {
    select when utility pulse where not ent:profile{"auto_assign_driver"}
    foreach ent:order_tracker.filter(function(v,k){v{"assigned_driver"}.isnull()}) setting (order)
    pre {
      bids = order{"bids"};
      client_eci = Subscriptions:established("Tx_role", "client")[0]{"Tx"};
    }
    
    if bids.length() > 0 then
      event:send({"eci": client_eci, // fake client pico - selects random bid
                  "domain":"client", "type":"bids_available", 
                  "attrs":{"order": order}});
  }
  
  //  If there was a client for store owners to view and select bids, this rule 
  //  would get the accepted bid from the client and go from there.
  rule store_select_bid {
    select when store accepted_bid
    pre {
      selected_bid = event:attrs{"bid"}
      order = ent:order_tracker{selected_bid{["bid", "orderId"]}};
    }
    
    if selected_bid then 
      event:send({"eci": selected_bid{["bid", "driver_channel"]}, 
                  "domain":"driver", "type":"assigned_delivery", 
                  "attrs":{"orderId": order{["details","orderId"]}}});
    
    fired {
      // update order_tracker
      ent:order_tracker{[order{["details", "orderId"]}, "assigned_driver"]} := selected_bid{["bid", "driver_channel"]};
      
      // send twilio message
      raise utility event "notify_customer" attributes {"to": order{["details", "customer_phone"]}}
    }
  }
  
  rule send_notification {
    select when utility notify_customer
    
    twilio:send_sms(event:attrs{"to"}, notification_from_phone_number, "Your flower delivery is on its way!")
  }
  // ***************************************************************************
  
  // Public facing rules *******************************************************
  rule new_bid {
    select when store new_bid
    
    pre {
      orderId = event:attrs{["bid", "orderId"]};
    }
    
    if orderId && event:attrs{["bid", "driverRank"]}.as("Number") >= ent:profile{"min_driver_rank"} then noop();
    
    fired {
      current_bids = ent:order_tracker{[orderId, "bids"]};
      updated_bids = current_bids.append({"bid": event:attrs{"bid"}, "received_at": time:now()});
      ent:order_tracker{[orderId, "bids"]} := updated_bids;
    }
  }
  
  rule order_delivered {
    select when store order_delivered
    pre {
      orderId = event:attrs{["delivery", "orderId"]};
      delivered_at = event:attrs{["delivery", "delivered_at"]};
      delivered_image = event:attrs{["delivery", "image"]};
    }
    
    if orderId && delivered_at then noop()
    
    fired {
      ent:order_tracker{[orderId, "delivered_at"]} := delivered_at;
      ent:order_tracker{[orderId, "delivered_image"]} := delivered_image;
    }
  }
  
  rule new_order_received {
    select when store new_order
    
    pre {
      orderId = random:uuid();
      mock_order = {"orderId": orderId, 
                    "ordered_at": time:now(), 
                    "cost": event:attrs{"cost"}.decode(),
                    "customer_phone": 2109134920,
                    "urgent": event:attrs{"urgent"}.isnull() => false | event:attrs{"urgent"}.decode()
      };
    }
    
    if orderId then noop();
    
    fired {
      ent:order_tracker{orderId} := {"details": mock_order, "bids": [], "deliverd_at": null, "assigned_driver": null};
      raise store event "broadcast_new_order" attributes mock_order
    }
  }
  
  rule alert_drivers {
    select when store broadcast_new_order
    foreach Subscriptions:established("Tx_role", "driver") setting (driver)
    pre {
      to_channel = driver{"Tx"};
      request = makeRequest(event:attrs)
    }
    
    event:send({"eci": to_channel, "domain":"driver", "type":"delivery_request", "attrs":request});

  }
  // ***************************************************************************
}
