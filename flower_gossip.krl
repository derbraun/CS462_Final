ruleset flower_gossip {

  meta {
    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.wrangler alias Wrangler
  }
  
  global {
    HIGH_PRIORITY = 10000
    
    n = 1
    
    getPeer = function(state) {
      subs = Subscriptions:established("Tx_role", "node").klog("All subs: ");
      // map the priority for each subscription
      priorities = subs.map(function(s){
        // If we don't have any state variable for a peer, you'll want to send that peer a message
        s_eci = s{"Tx"};
        state.klog("state") >< s_eci.klog("s in state?") =>
        getDifference(state[s_eci]).length() // how many rumors the peer is missing when compared to this gossiper's rumors
        | HIGH_PRIORITY
      }).klog("All priorities:");
      subs[priorities.index(priorities.sort("ciremun").klog("sorted priorities").head())].klog("Sub with highest priorities") // Choose the sub with the highest priority
    }
    
    prepareMessage = function(subscriber) {
      rand = random:integer(1);
      diff = (ent:state{subscriber} == null => ent:rumors.values().map(function(x){x["rumors"][0]})
      | getDifference(ent:state{subscriber}));
      chosen = rand == 1 =>
                ((diff.length() > 0) =>
                 diff[random:integer(diff.length()-1)]// get the CORRECT rumor, one they hadn't seen before
                 | createSeenMessage()) // If they've seen all your rumors, just send them a seen message
                 | createSeenMessage();
      (rand == 1 && diff.length() > 0) => getLowestSeq(diff, chosen)| chosen
    }
    
    // updates the subscriber's state, assuming m is a rumor message
    update = function(subscriber, m) {
      // Can you always increment sequence?
      mID = m["messageId"];
      mID_parts = mID.split(re#:#);
      ogID = mID_parts[0];
      // seqID = mID_parts[1];
      subs_state = ent:state[subscriber].defaultsTo({});
      subs_rumors = subs_state[ogID]["rumors"].defaultsTo([]).append(m);
      subs_new_state = subs_state.put(ogID, {"sequence": subs_state[ogID]["sequence"].defaultsTo(-1)+1, "rumors": subs_rumors});
      
      ent:state.defaultsTo({}).put(subscriber, subs_new_state)
    }
    
    send = defaction (subscriber, m, sender) {
      type = (m["messageId"] => "rumor" | "seen");
      event:send({"eci": subscriber, "eid": "node", "domain": "gossip", "type": type, "attrs": {"message":m, "sender":sender}})
    }

    // HELPER FUNCTIONS
    
    getLowestSeq = function(diff, chosen) {
      mID = chosen["messageId"];
      mID_parts = mID.split(re#:#);
      ogID = mID_parts[0];
      seq = mID_parts[1].decode();
      new_diff = diff.filter(function(m) {
        currmID = m["messageId"];
        currmID_parts = currmID.split(re#:#);
        currogID = currmID_parts[0];
        currseq = currmID_parts[1];
        ogID == currogID && currseq < seq
      });
      
      (new_diff.length == 0) => chosen | getLowestSeq(new_diff, new_diff[0])
    }
    
    sendAll = defaction (subscriber, ms, sender) {
      if ms.length() > 0 then
      every{
        send(subscriber, ms.head(), sender);
        sendAll(subscriber, ms.tail(), sender)
      }
    }
    
    updateAll = function (subscriber, ms) {
      done = ms.length() > 0 => update(subscriber, ms.head()) | true;
      done => true | updateAll(subscriber, ms.tail())
    }
    
    getDifference = function(peer_states) {
      // 1st filter finds all rumors structs in peer_states that have a lower seq than in rumors
      difference_rumor_structs = ent:rumors.filter(function(rumors_struct, ogID) {
        peer_states[ogID]["sequence"] < rumors_struct["sequence"]
      });
      // 2nd filter returns an array of rumors that don't have a match
      
      rumors_ar = difference_rumor_structs.map(function(dif_rumor_struct, originID) {
        dif_rumor_struct["rumors"]
      });
      rumors_ar.map(function(rumors, originID) {
        rumors.filter(function(rumor) {
          not (peer_states[originID]["rumors"] >< rumor)
        })
      }).values().reduce(function(a,b) {
        a.append(b)
      })
    }
    
    createSeenMessage = function() {
      ent:rumors.map(function(v,k) {
        v["sequence"]
      })
    }
  }
  
  rule hear_rumor {
    select when gossip rumor where ent:status != "off"
    
    pre {
      eci = event:attr("sender")
      rumor = event:attr("message")
      mID = rumor["messageId"]
      mID_parts = mID.split(re#:#)
      ogID = mID_parts[0]
      seqID = mID_parts[1]
      their_rumors = (ent:rumors[ogID]["rumors"] >< rumor) => ent:rumors[ogID]["rumors"] | ent:rumors[ogID]["rumors"].defaultsTo([]).append(rumor)
      current_sequence = ent:rumors[ogID]["sequence"].defaultsTo(0)
      
      sequence = (seqID - current_sequence == 1) => their_rumors.length()-1 | current_sequence  // if one was missed, but seq was it, fill in all the missing ones
      rumors = ent:rumors.defaultsTo({}).put(ogID, {"sequence": sequence, "rumors": their_rumors})
    }
    
    send_directive("Rumor \"" + mID + "\" received")
    
    always {
      ent:state := update(eci, rumor);
      ent:rumors := rumors
    }
  }
  
  rule hear_seen {
    select when gossip seen where ent:status != "off"
    
    // for each "seen", check if it has been seen and send it if it has not been
    foreach event:attr("message") setting (seq, ogID)
    pre {
      eci = event:attr("sender")
      rumors = ent:rumors[ogID]
      ms = (seq < rumors["sequence"] => rumors["rumors"].filter(function(r) {
        mID_parts = r["messageId"].split(re#:#);
        ogID = mID_parts[0];
        seqID = mID_parts[1];
        seqID > seq
      }) | null)
    }
    
    if ms then
      sendAll(eci, ms, meta:eci)
    
    fired {
      updateAll(eci, ms)
    }
    /*
    originIDs
    {
     "ABCD-1234-ABCD-1234-ABCD-125A": 3,
     "ABCD-1234-ABCD-1234-ABCD-129B": 5,
     "ABCD-1234-ABCD-1234-ABCD-123C": 10
    }
    */
  }
    
  rule gossip_beat {
    select when gossip heartbeat
    
    pre {
      state = ent:state.defaultsTo({}) // ent:state should contain the most recent seen object for each node
      peer = getPeer(state)
      subscriber = peer{"Tx"}
      sender = peer{"Rx"}
      m = prepareMessage(subscriber)
    }
    
    send(subscriber, m, sender)
    
    always{
      ent:state := (m["messageId"]) => update(subscriber, m) | state; // only update when m is a rumor, not a seen message
      // repeat the heartbeat later
      
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": n})
        attributes {}
    }
  }
  
  rule create_delivery_request_gossip {
    select when driver delivery_request
    
    pre {
      request = event:attr("request").decode()
      origin = meta:picoId
      rumors = ent:rumors.defaultsTo({})
      my_rumors = rumors[origin]["rumors"].defaultsTo([])
      message_id = origin + ":" + (my_rumors.length())
      new_rumor = request.put("messageId", message_id)
      my_rumors_updated = (my_rumors >< new_rumor => my_rumors | my_rumors.append(new_rumor))
      rumors_updated = rumors.put(origin, {"sequence": my_rumors_updated.length()-1, "rumors": my_rumors_updated})
    }
    
    always {
      ent:rumors := rumors_updated 
    }
  }
  
  rule change_processing {
    select when gossip process
    foreach event:schedule setting (e)
    pre {
      status = event:attr("status").defaultsTo("on")
    }
    if status == "off" then
    schedule:remove(e)  // stop the heartbeat from repeating
    always {
      ent:status := status
    }
  }
  
  rule request_gossip_subscription {
    select when gossip subscription_needed
    pre {
      attrs = event:attrs
      name = event:attr("name").defaultsTo("Gossip")
      partner_eci = event:attr("eci")
      my_eci = Wrangler:myself()["eci"]
    }      
    event:send({"eci":my_eci, "eid":subscription, "domain":"wrangler", "type":"subscription",
                "attrs":{"name": name,
                        "Rx_role": "node",
                        "Tx_role": "node",
                        "channel_type": "subscription",
                        "wellKnown_Tx": partner_eci
                }
    })
  }
  
  rule accept_subscription {
    select when wrangler inbound_pending_subscription_added
    
    always {
      raise wrangler event "pending_subscription_approval"
        attributes event:attrs
    }
  }
  
}
