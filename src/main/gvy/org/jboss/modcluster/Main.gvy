package org.jboss.modcluster
 
t = new WebSocketsTest()
t.performWsTunnelTest("TEST" , "ws://localhost:8000/websocket-hello-0.0.1/websocket/helloName", "Hello")
