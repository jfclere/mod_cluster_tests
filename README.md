# mod_cluster_tests
Tests using docker/podman to test mod_cluster

# testing websocket
Using com.ning.http.client.ws.WebSocketTextListener
To be able to run the test please use https://github.com/jfclere/httpd_websocket just build it:
```
git clone https://github.com/jfclere/httpd_websocket
cd https://github.com/jfclere/httpd_websocket
mvn install
cd ..
```
Build the groovy jar
```
mvn install
```
# run the tests
you need an httpd with the mod_cluster.so installed and the following piece in httpd.conf
```
LoadModule cluster_slotmem_module modules/mod_cluster_slotmem.so
LoadModule manager_module modules/mod_manager.so
LoadModule proxy_cluster_module modules/mod_proxy_cluster.so

  Listen 6666
  ManagerBalancerName mycluster
  EnableWsTunnel
  WSUpgradeHeader "websocket"
  <VirtualHost *:6666>
   <Directory />
       Require ip 127.0.0.1
    </Directory>

    KeepAliveTimeout 300
    MaxKeepAliveRequests 0

    EnableMCPMReceive
    ServerName localhost

    <Location /mod_cluster_manager>
       Require ip 127.0.0.1
    </Location>
  </VirtualHost>
```
