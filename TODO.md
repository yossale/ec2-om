# TODO

## Current Run:

ec2-52-209-11-140.eu-west-1.compute.amazonaws.com;


======================

1. Allow internal connections in the SG 
2. 


## Issues 

### Broken packages

When trying to install the mongo server using:

```sudo yum install -y https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-org-server-6.0.1-1.amzn2.x86_64.rpm```, 

we're getting the following error:
```
[ec2-user@ip-172-31-34-108 ~]$ sudo yum install -y https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/RPMS/mongodb-org-server-6.0.11-1.amzn2.x86_64.rpm
Last metadata expiration check: 0:04:41 ago on Mon Nov 13 15:35:02 2023.
mongodb-org-server-6.0.11-1.amzn2.x86_64.rpm                                                                                                                                                                                                     21 MB/s |  31 MB     00:01
Error:
 Problem: conflicting requests
  - nothing provides libcrypto.so.10()(64bit) needed by mongodb-org-server-6.0.11-1.amzn2.x86_64
  - nothing provides libcrypto.so.10(OPENSSL_1.0.2)(64bit) needed by mongodb-org-server-6.0.11-1.amzn2.x86_64
  - nothing provides libcrypto.so.10(libcrypto.so.10)(64bit) needed by mongodb-org-server-6.0.11-1.amzn2.x86_64
  - nothing provides libssl.so.10()(64bit) needed by mongodb-org-server-6.0.11-1.amzn2.x86_64
  - nothing provides libssl.so.10(libssl.so.10)(64bit) needed by mongodb-org-server-6.0.11-1.amzn2.x86_64
(try to add '--skip-broken' to skip uninstallable packages)
```

#### Solution: 

1. Find out which amazon linux version you're running: `grep -E -w 'VERSION|NAME|PRETTY_NAME' /etc/os-release` 
    * in my case, `PRETTY_NAME="Amazon Linux 2023"`

2. Install the relevant version of the enterprise edition from [here](https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-amazon/), 

Add the following content to the `/etc/yum.repos.d/mongodb-enterprise-7.0.repo` file: 
```
[mongodb-enterprise-7.0]
name=MongoDB Enterprise Repository
baseurl=https://repo.mongodb.com/yum/amazon/2023/mongodb-enterprise/7.0/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
```

run `sudo yum install -y mongodb-enterprise`

### Service won't start

```
[ec2-user@ip-172-31-37-49 ~]$ sudo systemctl status mongodb-mms
× mongodb-mms.service - MongoDB Ops Manager
     Loaded: loaded (/usr/lib/systemd/system/mongodb-mms.service; enabled; preset: disabled)
     Active: failed (Result: exit-code) since Mon 2023-11-13 16:31:59 UTC; 1h 2min ago
   Duration: 1min 12.507s
   Main PID: 28821 (code=exited, status=1/FAILURE)
        CPU: 56ms

Nov 13 16:30:46 ip-172-31-37-49.eu-west-1.compute.internal systemd[1]: Started mongodb-mms.service - MongoDB Ops Manager.
Nov 13 16:30:46 ip-172-31-37-49.eu-west-1.compute.internal mongodb-mms[28829]: tput: No value for $TERM and no -T specified
Nov 13 16:30:46 ip-172-31-37-49.eu-west-1.compute.internal mongodb-mms[28821]: Generating new Ops Manager private key...
Nov 13 16:30:47 ip-172-31-37-49.eu-west-1.compute.internal su[28842]: (to mongodb-mms) root on none
Nov 13 16:30:47 ip-172-31-37-49.eu-west-1.compute.internal su[28842]: pam_unix(su:session): session opened for user mongodb-mms(uid=992) by (uid=0)
Nov 13 16:31:59 ip-172-31-37-49.eu-west-1.compute.internal mongodb-mms[28821]: Preflight check failed.
Nov 13 16:31:59 ip-172-31-37-49.eu-west-1.compute.internal systemd[1]: mongodb-mms.service: Main process exited, code=exited, status=1/FAILURE
Nov 13 16:31:59 ip-172-31-37-49.eu-west-1.compute.internal systemd[1]: mongodb-mms.service: Failed with result 'exit-code'.
```

#### Solution
Usually, the issue is that it failed to start with the mongod. 
So try 
```
sudo systemctl status mongod
```
 or 
```
sudo systemctl start mongod
```
and then retry 
```
sudo systemctl start mongodb-mms
```


To view the logs: 
```
tail /opt/mongodb/mms/logs/mms0.log
```

### Installation fails because of libraries
add `sudo dnf upgrade -y --releasever=2023.2.20231030` to script
But 
- its long so consider if it's really crucial
- Think of making it use an automatic version
