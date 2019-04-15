ruleset flower_delivery_driver {
  meta {
    shares __testing
    use module io.picolabs.wrangler alias Wrangler
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    
    calcBid = function(){
      random:integer(1,10)
      // maybe do this by distance
    }
    
    isWithinMaxRange = function(location, maxDistance){
      true
    }
    
    getBid = function(request){
      { "driver_channel": Wrangler:myself(){"eci"}, // 
        "orderId" : request{"orderId"},
        "bidAmount": calcBid(),
        "driverRank": ent:profile{"rank"}} // 0 - 100
    }
  }
  
  rule initialize {
    select when wrangler ruleset_added where rids >< meta:rid
  
    always {
      ent:pending_bids := {};
      ent:profile := {
        "location" : {"lat": 1, "long": 1},
        "rank" : 50,
        "mile_rate": 4
      };
    }    
  }
  
  rule new_order_received {
    select when driver delivery_request
    pre {
      request = event:attrs{"request"}
      isInRange = isWithinMaxRange(request{"storeLocation"}, request{"maxDistance"})
    }
    
    if isInRange then noop();
    
    fired {
      
      raise utility event "send_bid" attributes request
    }
    
  }
  
  rule new_order_reveived_gossip {
    select when gossip rumor
    pre {
      request = event:attrs{"message"}
      already_placed_bid = ent:pending_bids{request{"orderId"}}
    }
    
    if already_placed_bid.isnull() then noop();
    
    fired {
      raise utility event "send_bid" attributes request
    }
    
  }
  
  rule send_bid {
    select when utility send_bid
    pre {
      request = event:attrs.klog("REQUEST")
      bid = getBid(request)
    }
    
    if bid then
        event:send({"eci": request{"sendBidTo"}, 
                  "domain":"store", "type":"new_bid", 
                  "attrs":{"bid": bid}});
    fired {
      ent:pending_bids{request{"orderId"}} := bid;
    }
    
  }
}
