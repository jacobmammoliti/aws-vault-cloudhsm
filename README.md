## Initialize CloudHSM

```shell
$ aws cloudhsmv2 describe-clusters --filters clusterIds=cluster-n5gphckjvn2 \
  --output text --query 'Clusters[].Certificates.ClusterCsr' > cluster-n5gphckjvn2_ClusterCsr.csr

$ openssl genrsa -aes256 -out customerCA.key 2048
...
Enter pass phrase for customerCA.key:
Verifying - Enter pass phrase for customerCA.key:

$ openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt


Enter pass phrase for customerCA.key:
...

$ openssl x509 -req -days 3652 -in cluster-n5gphckjvn2_ClusterCsr.csr \
                              -CA customerCA.crt \
                              -CAkey customerCA.key \
                              -CAcreateserial \
                              -out cluster-n5gphckjvn2_CustomerHsmCertificate.crt
...
Getting CA Private Key
Enter pass phrase for customerCA.key:

$ aws cloudhsmv2 initialize-cluster --cluster-id cluster-n5gphckjvn2 \
  --signed-cert file://cluster-n5gphckjvn2_CustomerHsmCertificate.crt \
  --trust-anchor file://customerCA.crt
{
    "State": "INITIALIZE_IN_PROGRESS",
    "StateMessage": "Cluster is initializing. State will change to INITIALIZED upon completion."
}
```

## Install Client on Vault Server and Create User for Vault

```shell
$ sudo apt update

$ wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client_latest_u18.04_amd64.deb
...
2020-11-11 01:39:51 (139 MB/s) - ‘cloudhsm-client_latest_u18.04_amd64.deb’ saved [1982292/1982292]

$ sudo apt install -y ./cloudhsm-client_latest_u18.04_amd64.deb
...
Processing triggers for ureadahead (0.100.0-21) ...
Processing triggers for systemd (237-3ubuntu10.42) ...

$ sudo /opt/cloudhsm/bin/configure -a 10.0.1.139
Updating server config in /opt/cloudhsm/etc/cloudhsm_client.cfg
Updating server config in /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg

$ /opt/cloudhsm/bin/cloudhsm_mgmt_util /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg
...
E2E enabled on server 0(10.0.1.139)
aws-cloudhsm>

aws-cloudhsm>enable_e2e
E2E enabled on server 0(10.0.1.139)

aws-cloudhsm>listUsers

aws-cloudhsm>loginHSM PRECO admin arctiq2020
...
changePswd success on server 0(10.0.1.139)

aws-cloudhsm> createUser CU vault_user vaultarctiq
creating user on server 0(10.0.1.139) success
```

## Install PKCS #11 Library

```shell
$ sudo service cloudhsm-client start

$ wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client-pkcs11_latest_u18.04_amd64.deb


$ sudo apt install -y ./cloudhsm-client-pkcs11_latest_u18.04_amd64.deb
```

When the installation succeeds, the PKCS #11 library is available at /opt/cloudhsm/lib.

## Install Vault
Install Vault on the EC2 instance with this Vault configuration.

```HCL
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "True"
}

storage "file" {
  path = "/opt/vault/data"
}

seal "pkcs11" { 
  lib            = "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so"
  slot           = "1"
  pin            = "vault_user:vaultarctiq"
  generate_key   = "true"
  key_label      = "vault"
  hmac_key_label = "vault"
}

disable_mlock    = "False"
ui               = "True"
```