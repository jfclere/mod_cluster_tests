# loop forever for an http code
# ALLOWTIMEOUT allows to ignore timeouts that might occur when the JVM is hanging.
CODE=$1
ALLOWTIMEOUT=$2
if [ -z "${CODE}" ]; then
  CODE=200
fi
if [ -z "${ALLOWTIMEOUT}" ]; then
   ALLOWTIMEOUT=0
else
   ALLOWTIMEOUT=1
fi
while true
do
  http_code=`curl -s -m10 -o /dev/null -w "%{http_code}" http://localhost:8000/testapp/test.jsp`
  if [ "${http_code}" != "${CODE}" ]; then
    echo "ERROR got: ${http_code} expects: ${CODE} `date`"
    if [ "${http_code}" != "000" ]; then
      exit 1
    else
      # http_code = "000" is timeout probably
      if [ ${ALLOWTIMEOUT} == "0" ]; then
         echo "Timeout NOT allowed"
         exit 1
      fi
    fi
  fi
  sleep 5
done
