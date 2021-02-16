#
# first stop running tomcats
stoptomcats () {
docker stop tomcat8081
docker stop tomcat8080
}

#
# Wait the nodes to go away
wait0 () {
NBNODES=2
while [ ${NBNODES} != 0 ]
do
  NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
  sleep 10
  date
done
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
nohup docker run --network=host -e tomcat_port=8080 --name tomcat8080 docker.io/kimonides/tomcat_mod_cluster &
nohup docker run --network=host -e tomcat_port=8081 --name tomcat8081 docker.io/kimonides/tomcat_mod_cluster &
}

#
# Wait until mod_cluster see 2 nodes
wait2 () {
NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
while [ ${NBNODES} != 2 ]
do
  NBNODES=`curl -s http://localhost:6666/mod_cluster_manager | grep Node | awk ' { print $3} ' | wc -l`
  sleep 10
  date
done
}

#
# main piece
#stoptomcats
#wait0
#removetomcats
#starttomcats
#wait2

#
# Copy testapp and wait for starting
#docker cp testapp tomcat8081:/usr/local/tomcat/webapps
#sleep 10

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
echo ${SESSIONCO}
NEWCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
echo ${NEWCO}
i=0
while [ "${NEWCO}" == "${SESSIONCO}" ]
do
  NEWCO=`curl -v http://localhost:8000/testapp/test.jsp -o /dev/null 2>&1 | grep Set-Cookie | awk '{ print $3 } ' | sed 's:;::'`
  i=`expr $i +1`
  if [ $i -gt 10 ]; then
    echo "Can't find the 2 webapps"
    exit 1
  fi
  echo "trying other webapp try: ${i}"
done

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
