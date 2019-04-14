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
        { "name": "getProfile"},
        { "name": "getOrders"}
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      { "domain": "store", "type": "update_profile", "attrs": ["min_driver_rank", "auto_assign_driver"]}
      ]
    }
    
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
          "storeLocation": ent:profile{"storeLocation"}
        }
      }
    }
    
  }
  
  rule initialize {
    select when wrangler ruleset_added where rids >< meta:rid
  
    always {
      ent:order_tracker := {};
      ent:profile := {"min_driver_rank": 50, 
                      "auto_assign_driver": true, 
                      "storeLocation":{"lat": 40.251887, "long": -111.649332}};
      // ent:bid_channel := Wrangler:createChannel(null, "bid_channel", "bid_channel", null)
    }    
  }
  
  rule new_bid {
    select when store new_bid
    
    pre {
      orderId = event:attrs{["bid", "orderId"]};
    }
    
    if orderId then noop();
    
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
    }
    
    if orderId && delivered_at then noop()
    
    fired {
      ent:order_tracker{[orderId, "delivered_at"]} := delivered_at;
    }
  }
  
  rule new_order_received {
    select when store new_order
    
    pre {
      orderId = random:uuid();
      mock_order = {"orderId": orderId, 
                    "ordered_at": time:now(), 
                    "cost": event:attrs{"cost"}.decode(),
                    "urgent": event:attrs{"urgent"}.isnull() => false | event:attrs{"urgent"}.decode()
      };
    }
    
    if orderId then noop();
    
    fired {
      ent:order_tracker{orderId} := {"details": mock_order, "bids": [], "deliverd_at": null};
      raise store event "broadcast_new_order" attributes mock_order
    }
  }
  
  rule alert_drivers {
    select when store broadcast_new_order
    foreach Subscriptions:established("Tx_role", "driver") setting (driver)
    pre {
      to_channel = driver{"Tx"};
      request = makeRequest(event:attrs).klog("REQ")
    }
    
    event:send({"eci": to_channel, "domain":"driver", "type":"delivery_request", "attrs":request});

  }
  
  // Helper events *************************************************************
  rule update_profile {
    select when store update_profile
    
    pre {
      min_driver_rank = event:attrs{"min_driver_rank"}.decode();
      auto_assign_driver = event:attrs{"auto_assign_driver"}.decode().klog("HERE");
    }
    
    always {
      ent:profile{"min_driver_rank"} := min_driver_rank.isnull() => ent:profile{"min_driver_rank"} | min_driver_rank;
      ent:profile{"auto_assign_driver"} := auto_assign_driver.isnull() => ent:profile{"auto_assign_driver"} | auto_assign_driver;
    }
  }
}
