# AWS CloudHSM with HashiCorp Vault

## Deploy Everything with Terraform

```bash
$ export AWS_ACCESS_KEY_ID=""

$ export AWS_SECRET_ACCESS_KEY=""

$ terraform init

$ terraform apply -auto-approve
...
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

hsm_cluster_id = cluster-cjk26onnbtr
...
```

## Initialize CloudHSM

```bash
$ export HSM_CLUSTER_ID=cluster-cjk26onnbtr

$ aws cloudhsmv2 describe-clusters --filters clusterIds=$HSM_CLUSTER_ID \
  --output text --query 'Clusters[].Certificates.ClusterCsr' > $HSM_CLUSTER_ID_ClusterCsr.csr

$ openssl genrsa -aes256 -out customerCA.key 2048
...
Enter pass phrase for customerCA.key:
Verifying - Enter pass phrase for customerCA.key:

$ openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt


Enter pass phrase for customerCA.key:
...

$ openssl x509 -req -days 3652 -in $HSM_CLUSTER_ID_ClusterCsr.csr \
  -CA customerCA.crt -CAkey customerCA.key -CAcreateserial \
  -out $HSM_CLUSTER_ID_CustomerHsmCertificate.crt
...
Getting CA Private Key
Enter pass phrase for customerCA.key:

$ aws cloudhsmv2 initialize-cluster --cluster-id $HSM_CLUSTER_ID \
  --signed-cert file://$HSM_CLUSTER_ID_CustomerHsmCertificate.crt \
  --trust-anchor file://customerCA.crt
{
    "State": "INITIALIZE_IN_PROGRESS",
    "StateMessage": "Cluster is initializing. State will change to INITIALIZED upon completion."
}
```

## Install Client on Vault Server and Create User for Vault

```bash
$ sudo apt update

$ wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client_latest_u18.04_amd64.deb
...
2020-11-11 01:39:51 (139 MB/s) - ‘cloudhsm-client_latest_u18.04_amd64.deb’ saved [1982292/1982292]

$ sudo apt install -y ./cloudhsm-client_latest_u18.04_amd64.deb
...
Processing triggers for ureadahead (0.100.0-21) ...
Processing triggers for systemd (237-3ubuntu10.42) ...

# get the IP of the HSM
$ sudo /opt/cloudhsm/bin/configure -a 10.0.1.139
Updating server config in /opt/cloudhsm/etc/cloudhsm_client.cfg
Updating server config in /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg

# copy customerCA.crt to /opt/cloudhsm/etc/customerCA.crt

# switch to HSM cli
$ /opt/cloudhsm/bin/cloudhsm_mgmt_util /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg
...
E2E enabled on server 0(10.0.1.139)
aws-cloudhsm>

aws-cloudhsm>enable_e2e
E2E enabled on server 0(10.0.1.139)

aws-cloudhsm>listUsers

aws-cloudhsm>loginHSM PRECO admin password
loginHSM success on server 0(10.0.1.114)

aws-cloudhsm>changePswd PRECO admin arctiqvault
...
changePswd success on server 0(10.0.1.139)

aws-cloudhsm>quit
disconnecting from servers, please wait...

# switch back to HSM cli to create vault user
$ /opt/cloudhsm/bin/cloudhsm_mgmt_util /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg
...
E2E enabled on server 0(10.0.1.139)
aws-cloudhsm>createUser CU vault_user vaultarctiq
Creating User vault_user(CU) on 1 nodes
createUser success on server 0(10.0.1.114)

```

## Install PKCS #11 Library

```bash
$ sudo service cloudhsm-client start

$ wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client-pkcs11_latest_u18.04_amd64.deb
...
2020-11-11 02:21:33 (45.0 MB/s) - ‘cloudhsm-client-pkcs11_latest_u18.04_amd64.deb’ saved [237930/237930]

$ sudo apt install -y ./cloudhsm-client-pkcs11_latest_u18.04_amd64.deb
...
Unpacking cloudhsm-client-pkcs11 (3.2.1-1) ...
Setting up cloudhsm-client-pkcs11 (3.2.1-1) ...
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