ruleset flower_delivery_driver {
  meta {
    shares __testing, getProfile, isWithinMaxRange, getKey
    use module io.picolabs.wrangler alias Wrangler
    use module key_module
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" },
      { "name": "getProfile" },
      { "name": "isWithinMaxRange" },
      { "name": "getKey"}
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      { "domain": "utility", "type": "update_location", "attrs": [ "lat", "long" ] },
      { "domain": "utility", "type": "update_rate", "attrs": [ "rate" ] },
      { "domain": "utility", "type": "update_rank", "attrs": [ "rank" ] }
      ]
    }
    
    getProfile = function(){ent:profile}
    getKey = function(){keys:google{"api_key"}}
    
    calcBid = function(){
      random:integer(1,10)
      // maybe do this by distance
    }
    
    getDistance = function(origin, destination){
      url = "https://maps.googleapis.com/maps/api/distancematrix/json?units=imperial&"
        + "origins=" + origin
        + "&destinations=" + destination
        + "&key=" + keys:google{"api_key"};
      http:get(url){"content"}.decode(){"rows"}[0]{"elements"}[0]{["distance", "value"]}
    }
    
    isWithinMaxRange = function(location, maxDistance){
      origin = location{"lat"} + "," + location{"long"};
      destination = ent:profile{["location", "lat"]} + "," + ent:profile{["location", "long"]};
      maxDistance = maxDistance * 1609.344; // miles to meters
      distance = getDistance(origin, destination); // in meters
      distance <= maxDistance;

    }
    
    getBid = function(request){
      { "driver_channel": Wrangler:myself(){"eci"}, // 
        "orderId" : request{"orderId"},
        "bidAmount": calcBid(),
        "driverRank": ent:profile{"rank"}} // 0 - 100
    }
  }
  
  // Logic rules ***************************************************************
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
      raise driver event "send_bid" attributes request
    }
    
  }
  
  rule send_bid {
    select when driver send_bid
    pre {
      request = event:attrs.klog("REQUEST")
      bid = getBid(request)
    }
    
    if bid then
        event:send({"eci": request{"sendBidTo"}, 
                  "domain":"store", "type":"new_bid", 
                  "attrs":{"bid": bid}});
    fired {
      ent:pending_bids{request{"orderId"}} := {"bid": bid, "request": request};
    }
    
  }
  
  rule delivered {
    select when user order_delivered
    pre {
      returnObj = { "delivery": {
                      "orderId": event:attrs{"orderId"},
                      "delivered_at": "Sometime",
                      "image": "AnImage"
                      } 
                  };
    }
    
    if event:attrs{"orderId"} then
      event:send({"eci": ent:pending_bids{["orderId", "request", "sendBidTo"]}, 
                  "domain":"store", "type":"order_delivered", 
                  "attrs":{"delivery": returnObj}});
  }
  // ***************************************************************************
  
  // Utility rules *************************************************************
    
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
  
  rule update_location {
    select when utility update_location
    always {
      ent:profile{["location", "lat"]} := event:attrs{"lat"}.decode();
      ent:profile{["location", "long"]} := event:attrs{"long"}.decode();
    }
  }
  
  rule update_rate {
    select when utility update_rate
    always {
      ent:profile{"mile_rate"} := event:attrs{"rate"}.decode();
    }
  }
  
  rule update_rank {
    select when utility update_rank
    always {
      ent:profile{"rank"} := event:attrs{"rank"}.decode();
    }
  }
  // ***************************************************************************
}
