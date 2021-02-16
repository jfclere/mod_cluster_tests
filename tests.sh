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
# Wait the nodes to go away
wait0 () {
curl -s http://localhost:6666/mod_cluster_manager -o /dev/null
if [ $? -ne 0 ]; then
  echo "httpd no started or something VERY wrong"
  exit 1
fi
NBNODES=2
while [ ${NBNODES} != 0 ]
do
  NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
  sleep 10
  echo "Wating for the node to go away: `date`"
done
curl -s http://localhost:6666/mod_cluster_manager -o /dev/null
if [ $? -ne 0 ]; then
  echo "httpd no started or something VERY wrong"
  exit 1
fi
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
# Wait until mod_cluster see 2 nodes
wait2 () {
NBNODES=0
while [ ${NBNODES} != 2 ]
do
  NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
  sleep 10
  echo "Wating for 2 node to be up: `date`"
done
}

#
# main piece
stoptomcats
wait0 || exit 1
removetomcats
starttomcats || exit 1
wait2

#
# Copy testapp and wait for starting
docker cp testapp tomcat8081:/usr/local/tomcat/webapps
sleep 10

# basic 200 and 404 tests.
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
echo "stopping one node and doing requests..."
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
  fi
  i=`expr $i + 1`
done
if [ ${CODE} != "200" ]; then
  echo "Something was wrong... got: ${CODE}"
  exit 1
fi
