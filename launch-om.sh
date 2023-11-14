PURPOSETAG=other
EXPIREON=2023-12-31

source config.sh

OM_VERSION=https://downloads.mongodb.com/on-prem-mms/rpm/mongodb-mms-6.0.9.100.20230201T2148Z.x86_64.rpm

export AWS_PAGER=""
# start instance to run Ops Manager
# t3a.medium has 4GB RAM - should be enough for a demo config
echo "Spinning up AWS instance for Ops Manager"
aws ec2 run-instances --image-id $IMAGE --count 1 --instance-type t3a.xlarge --key-name $KEYNAME \
  --security-group-ids $SECGROUP --block-device-mappings '[{"DeviceName": "/dev/xvda", "Ebs": {"DeleteOnTermination": true, "VolumeSize": 100, "VolumeType": "gp3"}}]' \
  --tag-specification "ResourceType=instance,Tags=[{Key=Name, Value=\"$NAMETAG-om\"},{Key=owner, Value=\"$OWNERTAG\"}, {Key=expire-on,Value=\"$EXPIREON\"}, {Key=purpose,Value=\"$PURPOSETAG\"}]" > /dev/null

echo "Done"
# wait a couple seconds that the instance is up
sleep 10

res=$(aws ec2 describe-instances --filters "Name=tag:owner,Values=$OWNERTAG" "Name=tag:Name,Values=$NAMETAG-om" "Name=instance-state-name,Values=running")
export PUBDNS=$(echo $res | jq -r '.Reservations[0].Instances[0].PublicDnsName')
PRIVDNS=$(echo $res | jq -r '.Reservations[0].Instances[0].PrivateDnsName')

echo "Public DNS is $PUBDNS; waiting for ssh"

sleep 1
nc -z $PUBDNS 22
until test $? -eq 0
do
  sleep 1
  printf "."
  nc -z $PUBDNS 22
done

BASEURL='https://repo.mongodb.com/yum/amazon/2023/mongodb-enterprise/7.0/\$basearch/'
# install mongo, shell, and OM rpms

ssh -i $KEYPATH -oStrictHostKeyChecking=no ec2-user@$PUBDNS <<EOF

sudo dnf upgrade -y --releasever=2023.2.20231030
sudo yum install -y $OM_VERSION

sudo tee -a /etc/yum.repos.d/mongodb-enterprise-7.0.repo <<-RPM_FILE
[mongodb-enterprise-7.0]
name=MongoDB Enterprise Repository
baseurl=$BASEURL
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
RPM_FILE
sudo yum install -y mongodb-enterprise
sudo systemctl start mongod

sudo tee -a /opt/mongodb/mms/conf/conf-mms.properties <<-CONF_FILE
mms.ignoreInitialUiSetup=true
mms.centralUrl=http://$PUBDNS:8080
mms.https.ClientCertificateMode=none
mms.fromEmailAddr=admin@localhost.com
mms.replyToEmailAddr=admin@localhost.com
mms.adminEmailAddr=admin@localhost.com
mms.emailDaoClass=SIMPLE_MAILER
mms.mail.transport=smtp
mms.mail.hostname=localhost
mms.mail.port=25
mms.user.invitationOnly=true
CONF_FILE

sudo mkdir /snapshots
sudo chown mongodb-mms:mongodb-mms /snapshots
sudo mkdir /heads
sudo chown mongodb-mms:mongodb-mms /heads

sudo systemctl status mongod
sudo systemctl start mongodb-mms
sudo systemctl status mongodb-mms

EOF

if [ $? -eq 0 ]; then
  echo "Mongod and Ops Manager are installed, and starting. Host is $PUBDNS - We'll be creating the first user now when it's up"
else
  echo "Oops, something wrong happened"
  exit 1
fi

sleep 5
nc -z $PUBDNS 8080
until test $? -eq 0
do
  echo "Waiting"
  sleep 5
  nc -z $PUBDNS 8080
done

echo "Can connect to $PUBDNS:8080"

export MY_IP=$(curl -4 ifconfig.me)
USERNAME=admin@localhost.com
PASSWORD=abc_ABC1
FIRST=Admin
LAST=Adminsson

echo "My IP is $MY_IP"

res=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"firstName\":\"$FIRST\",\"lastName\":\"$LAST\"}" \
 http://$PUBDNS:8080/api/public/v1.0/unauth/users\?whitelist\=$MY_IP)

PUBKEY=$(echo $res | jq -r '.programmaticApiKey.publicKey')
PRIVKEY=$(echo $res | jq -r '.programmaticApiKey.privateKey')

echo "API key is $PUBKEY:$PRIVKEY"

# provision backup
curl --digest --user "$PUBKEY:$PRIVKEY" -s -X POST \
 -H "Content-Type: application/json" -d "{\"id\": \"filesystemStore\", \"storePath\": \"/snapshots\", \"assignmentEnabled\": true, \"wtCompressionSetting\": \"NONE\", \"mmapv1CompressionSetting\": \"NONE\"}" \
 http://$PUBDNS:8080/api/public/v1.0/admin/backup/snapshot/fileSystemConfigs

curl --digest --user "$PUBKEY:$PRIVKEY" -s -X POST \
 -H "Content-Type: application/json" -d "{\"id\": \"oplogStore\", \"uri\": \"mongodb://localhost:27017\", \"assignmentEnabled\": true}" \
 http://$PUBDNS:8080/api/public/v1.0/admin/backup/oplog/mongoConfigs

 curl --digest --user "$PUBKEY:$PRIVKEY" -s -X POST \
  -H "Content-Type: application/json" -d "{\"id\": \"syncStore\", \"uri\": \"mongodb://localhost:27017\", \"assignmentEnabled\": true}" \
  http://$PUBDNS:8080/api/public/v1.0/admin/backup/sync/mongoConfigs



# create org & Project
ORG_ID=$(curl --user "$PUBKEY:$PRIVKEY" --digest \
-s -X POST -H "Content-Type: application/json" \
--data "{\"name\":\"demo-org\"}" \
http://$PUBDNS:8080/api/public/v1.0/orgs | jq -r '.id')
echo "Org id: $ORG_ID"

# invite user as org owner
curl --user "$PUBKEY:$PRIVKEY" --digest \
-s -X POST -H "Content-Type: application/json" \
--data "{\"roles\": [ \"ORG_OWNER\" ], \"username\": \"admin@localhost.com\" }" \
http://$PUBDNS:8080/api/public/v1.0/orgs/$ORG_ID/invites

# create project - for some reason it yields a 500, so we create and then list and get the new ID
res=$(curl --user "$PUBKEY:$PRIVKEY" --digest \
 -s -X POST -H "Content-Type: application/json" \
 --data "{\"name\":\"demo-project\",\"orgId\":\"$ORG_ID\"}" \
 http://$PUBDNS:8080/api/public/v1.0/groups)
AGENT_API_KEY=$(echo $res | jq -r '.agentApiKey')
PROJECT_ID=$(echo $res | jq -r '.id')

echo "Project is $PROJECT_ID, Agent API Key is $AGENT_API_KEY"

./launch-hosts.sh $PUBDNS $PROJECT_ID $AGENT_API_KEY


# enable backup daemon
curl --digest --user "$PUBKEY:$PRIVKEY" -s -X PUT \
  -H "Content-Type: application/json" -d "{\"assignmentEnabled\": true, \"configured\": true, \"machine\": {\"headRootDirectory\": \"/heads/\", \"machine\": \"$PRIVDNS\"}}" \
  http://$PUBDNS:8080/api/public/v1.0/admin/backup/daemon/configs/$PRIVDNS

echo "-----"
echo "All servers started; go to http://$PUBDNS:8080 and log in with admin@localhost.com / abc_ABC1"
echo "Global owner API KEY: $PUBKEY:$PRIVKEY"
echo "Enjoy!"
open http://$PUBDNS:8080
