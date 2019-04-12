ruleset store {
  meta {
    use module io.picolabs.subscription alias Subscriptions
    
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
  }
  
  rule initialize {
    select when wrangler ruleset_added where rids >< meta:rid
  
    always {
      ent:order_tracker := {};
      ent:profile := {"min_driver_rank": 50, "auto_assign_driver": true};
    }    
  }
  
  rule new_bid {
    select when store new_bid
    
    noop();
    
    fired {
      current_bids = ent:order_tracker{[event:attrs{"id"}, "bids"]};
      updated_bids = current_bids.append({"bid": event:attrs{"bid"}, "received_at": time:now()});
      ent:order_tracker{[event:attrs{"id"}, "bids"]} := updated_bids;
    }
  }
  
  rule order_delivered {
    select when store order_delivered
    
  }
  
  rule new_order_received {
    select when store new_order_received
    
    noop();
    
    fired {
      ent:order_tracker{event:attrs{"id"}} := {"details": event:attrs, "bids": [], "deliverd_at": null};
      raise store event "broadcast_new_order" 
    }
  }
  
  rule alert_drivers {
    select when store broadcast_new_order
    
    // send driver:delivery_request
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
