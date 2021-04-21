# loop forever for an http code
# ALLOWTIMEOUT allows to ignore timeouts that might occur when the JVM is hanging.
CODE=$1
ALLOWTIMEOUT=$2
if [ -z "${CODE}" ]; then
  CODE=200
fi
if [ -z "${ALLOWTIMEOUT}" ]; then
   ALLOWTIMEOUT=false
else
   ALLOWTIMEOUT=true
fi
while true
do
  http_code=`curl -s -m10 -o /dev/null -w "%{http_code}" http://localhost:8000/testapp/test.jsp`
  if [ "${http_code}" != "${CODE}" ]; then
    echo "ERROR got: ${http_code} expects: ${CODE} `date`"
    if [ "${http_code}" != "000" && ${ALLOWTIMEOUT} ]; then
      exit 1
    fi
  fi
  sleep 5
done
