#
# first stop running tomcats
stoptomcats () {
docker ps | grep tomcat8081
if [ $? -eq 0 ]; then
  echo "Stopping tomcat8081"
  docker stop tomcat8081
    if [ $? -ne 0 ]; then
      echo "Can't stop tomcat8081"
    exit 1
  fi
fi
docker ps | grep tomcat8080
if [ $? -eq 0 ]; then
  echo "Stopping tomcat8080"
  docker stop tomcat8080
  if [ $? -ne 0 ]; then
    echo "Can't stop tomcat8080"
    exit 1
  fi
fi
}

#
# Wait the nodes to go away or start
waitnodes () {
nodes=$1
curl -s http://localhost:6666/mod_cluster_manager -o /dev/null
if [ $? -ne 0 ]; then
  echo "httpd no started or something VERY wrong"
  exit 1
fi
NBNODES=-1
while [ ${NBNODES} != ${nodes} ]
do
  NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
  sleep 10
  echo "Waiting for ${nodes} node to be ready: `date`"
done
curl -s http://localhost:6666/mod_cluster_manager -o /dev/null
if [ $? -ne 0 ]; then
  echo "httpd no started or something VERY wrong"
  exit 1
fi
echo "Waiting for the node DONE: `date`"
}

#
# remove them
removetomcats () {
docker container rm tomcat8081
docker container rm tomcat8080
}

#
# Start them again
starttomcats() {
echo "Starting tomcat8080..."
nohup docker run --network=host -e tomcat_port=8080 --name tomcat8080 docker.io/kimonides/tomcat_mod_cluster &
if [ $? -ne 0 ]; then
  echo "Can't start tomcat8080"
  exit 1
fi
sleep 10
echo "Starting tomcat8081..."
nohup docker run --network=host -e tomcat_port=8081 --name tomcat8081 docker.io/kimonides/tomcat_mod_cluster &
if [ $? -ne 0 ]; then
  echo "Can't start tomcat8081"
  exit 1
fi
echo "2 Tomcats started..."
}

#
# Write message do know where we are at
#
writemessage() {
MESS=$1
echo "***************************************************************"
echo "Doing test: $MESS"
echo "***************************************************************"
}

jdbsuspend() {
rm -f /tmp/testpipein
mkfifo /tmp/testpipein
rm -f /tmp/testpipeout
mkfifo /tmp/testpipeout
sleep 10000 > /tmp/testpipein &
docker exec -it tomcat8080 jdb -attach 6660 < /tmp/testpipein > /tmp/testpipeout &
echo "suspend" > /tmp/testpipein
cat < /tmp/testpipeout &
}
jdbexit() {
cat > /tmp/testpipeout &
echo "exit" > /tmp/testpipein
}

#
# main piece
stoptomcats
waitnodes 0  || exit 1
removetomcats
starttomcats || exit 1
waitnodes 2 

#
# Copy testapp and wait for starting
docker cp testapp tomcat8081:/usr/local/tomcat/webapps
sleep 10

# basic 200 and 404 tests.
writemessage "basic 200 and 404 tests"
CODE=`curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/testapp/test.jsp`
if [ ${CODE} != "200" ]; then
  echo "Failed can't rearch webapp"
  exit 1
fi
CODE=`curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/testapp/toto.jsp`
if [ ${CODE} != "404" ]; then
  echo "Failed should get 404"
  exit 1
fi

#
# Sticky (yes there is only one app!!!)
writemessage "sticky one app"
SESSIONCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
if [ "${SESSIONCO}" == "" ];then
  echo "Failed no sessionid in curl output..."
  curl -v http://localhost:8000/testapp/test.jsp
fi
echo ${SESSIONCO}
NEWCO=`curl -v --cookie "${SESSIONCO}" http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
if [ "${NEWCO}" != "" ]; then
  echo "Failed not sticky received : ${NEWCO}???"
  exit 1
fi

#
# Copy testapp and wait for starting
docker cp testapp tomcat8080:/usr/local/tomcat/webapps
sleep 10

#
# Sticky (yes there is now 2 apps
writemessage "sticky 2 app"
SESSIONCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
NODE=`echo ${SESSIONCO} | awk -F = '{ print $2 }' | awk -F . '{ print $2 }'`
echo "first: ${SESSIONCO} node: ${NODE}"
NEWCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
NEWNODE=`echo ${NEWCO} | awk -F = '{ print $2 }' | awk -F . '{ print $2 }'`
echo "second: ${NEWCO} node: ${NEWNODE}"
echo "Checking we can reach the 2 nodes"
i=0
while [ "${NODE}" == "${NEWNODE}" ]
do
  NEWCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
  NEWNODE=`echo ${NEWCO} | awk -F = '{ print $2 }' | awk -F . '{ print $2 }'`
  i=`expr $i + 1`
  if [ $i -gt 20 ]; then
    echo "Can't find the 2 webapps"
    exit 1
  fi
  if [ "${NEWNODE}" == "" ]; then
    echo "Can't find node in request"
    exit 1
  fi
  echo "trying other webapp try: ${i}"
done
echo "${i} try gives: ${NEWCO} node: ${NEWNODE}"

#
# still sticky
CO=`curl -v --cookie "${SESSIONCO}" http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
if [ "${CO}" != "" ]; then
  echo "Failed not sticky received : ${CO}???"
  exit 1
fi
CO=`curl -v --cookie "${NEWCO}" http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
if [ "${CO}" != "" ]; then
  echo "Failed not sticky received : ${CO}???"
  exit 1
fi

#
# Stop one of the while running requests.
writemessage "sticky: stopping one node and doing requests..."
NODE=`echo ${NEWCO} | awk -F = '{ print $2 }' | awk -F . '{ print $2 }'`
echo $NODE
PORT=`curl http://localhost:6666/mod_cluster_manager | grep Node | grep $NODE | sed 's:)::' | awk -F : '{ print $3 } '`
echo "Will stop ${PORT} corresponding to ${NODE} and cookie: ${NEWCO}"
CODE="200"
i=0
while [ "$CODE" == "200" ]
do
  if [ $i -gt 100 ]; then
    echo "Done remaining tomcat still answering!"
    break
  fi
  CODE=`curl -s -o /dev/null -w "%{http_code}" --cookie "${NEWCO}" http://localhost:8000/testapp/test.jsp`
  if [ $i -eq 0 ]; then
    # stop the tomcat
    echo "tomcat${PORT} being stopped"
    docker stop tomcat${PORT}
    docker container rm tomcat${PORT}
  fi
  i=`expr $i + 1`
done
if [ ${CODE} != "200" ]; then
  echo "Something was wrong... got: ${CODE}"
  curl -v --cookie "${NEWCO}" http://localhost:8000/testapp/test.jsp
  exit 1
fi

# restart the tomcat
nohup docker run --network=host -e tomcat_port=${PORT} --name tomcat${PORT} docker.io/kimonides/tomcat_mod_cluster &

# now try to test the websocket
writemessage "testing websocket"
mvn dependency:copy -Dartifact=org.apache.tomcat:websocket-hello:0.0.1:war  -DoutputDirectory=.
docker cp websocket-hello-0.0.1.war tomcat8080:/usr/local/tomcat/webapps
docker cp websocket-hello-0.0.1.war tomcat8081:/usr/local/tomcat/webapps
# Put the testapp in the  tomcat we restarted.
docker cp testapp tomcat${PORT}:/usr/local/tomcat/webapps
sleep 10
java -jar target/test-1.0.jar WebSocketsTest
if [ $? -ne 0 ]; then
  echo "Something was wrong... with websocket tests"
  exit 1
fi

#
# Test a keepalived connection finds the 2 webapps on each tomcat
docker cp testapp tomcat8080:/usr/local/tomcat/webapps/testapp1
docker cp testapp tomcat8081:/usr/local/tomcat/webapps/testapp2
sleep 10
java -jar target/test-1.0.jar HTTPTest
if [ $? -ne 0 ]; then
  echo "Something was wrong... with HTTP tests"
  exit 1
fi

#
# check that hanging tomcat will be removed
#
writemessage "hanging a tomcat checking it is removed after a while no requests"
PORT=8080
docker cp setenv.sh tomcat${PORT}:/usr/local/tomcat/bin
docker commit tomcat${PORT} docker.io/kimonides/tomcat_mod_cluster-debug
docker stop tomcat${PORT}
docker container rm tomcat${PORT}
waitnodes 1 
# start the node.
nohup docker run --network=host -e tomcat_port=${PORT} --name tomcat${PORT} docker.io/kimonides/tomcat_mod_cluster-debug &
sleep 10
docker exec tomcat8080 jdb -attach 6660 < continue.txt
waitnodes 2  || exit 1
echo "2 tomcat started"
# hang the node.
# jdb and a pipe to hang the tomcat.
jdbsuspend
waitnodes 1  || exit 1
echo "1 tomcat hanging and gone"
jdbexit
# the tomcat is comming up again
waitnodes 2  || exit 1
echo "the tomcat is back"

# same test with requests
# do requests in a loop
writemessage "hanging tomcat removed after a while with requests"
bash curlloop.sh 200 1 &
jdbsuspend
waitnodes 1  || exit 1
ps -ef | grep curlloop | grep -v grep
if [ $? -ne 0 ]; then
  echo "curlloop.sh FAILED!"
  exit 1
fi
ps -ef | grep curlloop | grep -v grep | awk ' { print $2 } ' | xargs kill
jdbexit
# the tomcat is comming up again
waitnodes 2  || exit 1

# same test with requets but stop the other tomcat
writemessage "single hanging tomcat removed after a while with requests"
PORT=8081
docker stop tomcat${PORT}
docker container rm tomcat${PORT}
waitnodes 1  || exit 1
jdbsuspend
bash curlloop.sh 503 1 &
waitnodes 0  || exit 1
ps -ef | grep curlloop | grep -v grep
if [ $? -ne 0 ]; then
  echo "curlloop.sh FAILED!"
  exit 1
fi
ps -ef | grep curlloop | grep -v grep | awk ' { print $2 } ' | xargs kill
jdbexit
# the tomcat is comming up again
waitnodes 1  || exit 1

# cleanup at the end
stoptomcats
waitnodes 0  || exit 1
removetomcats
echo "Done!"
