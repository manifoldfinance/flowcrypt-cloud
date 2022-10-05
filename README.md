`version: 2022-02`

# FlowCrypt Google Workspace Key Manager

This software allows you to protect your organisation's Google Workspace data with strong Client Side Encryption (CSE).

Google Workspace Key Manager (WKM) is on-prem software service which wraps and unwraps (encrypts/decrypts) Data Encryption Keys (DEKs) for use in Google Workspace web and native applications such as Google Drive and Google Docs. 

Key Encryption Keys (KEKs) are derived on the fly using a set of Master Secrets, which in turn may be stored using your existing infrastructure, on any [PKCS#11](#pkcs11-integration) or [KMIP](#kmip-integration)-compatible Hardware Security Module (HSM) or software key management system (KMS). KEK-encrypted Data Encryption Keys (DEKs) are then uploaded to GSuite along with encrypted data.

In Google terminology, our WKM is referred to as "KACLS - Key ACL Service".

The API is a REST API with JSON body requests and responses, accessed by Google Workspace web app and Google Workspace client software. SSL connections can be either terminated in the WKM, or you can use SSL terminating reverse proxy (in which case you can set `api.https.enabled=false` in the config file).

## Requirements

All requirements described in [On-prem deployment requirements](https://flowcrypt.com/docs/technical/enterprise/configuration/requirements.html) plus the following:

| Type | Requirement |
|:--------|:----------|
| [Key Storage](#section-store) | The WKM derives keys on the fly from Master Secrets. You have a choice on how to load Master Secrets during startup, from properties file, stdin, a PKCS#11 or a KMIP-1.0 compatible Key Store (such as Gemalto Safenet KeySecure over KMIP, Fortanix SDKMS and Equinix SmartKey over PKCS#11) |
| Networking | WKM must be accessible on an internal URL from client devices, with TLS cert trusted by client. The instance should not be accessible from public internet, but it needs limited outward access to the internet to fetch IdP JWK for user authentication and Google JWK for request authorization. |

## Distribution and deployment

FlowCrypt WKM is distributed as a zip file containing:

| Filename | Description |
|:--- |:--- |
| `flowcrypt-workspace-key-manager.jar` | Runnable Java JAR
| `flowcrypt-workspace-key-manager.properties` | Default config
| `flowcrypt-workspace-key-manager-docs.md` | This documentation
| `LICENSE.txt` | License file (proprietary)

For deployment, install OpenJDK JRE, copy the `.jar` and the `.properties` file, and edit the properties file before running.

*Windows only* If your OS does not use UTF-8 file encoding by default, then you should ensure the app uses UTF-8 encoding.
UTF-8 support is required by the Google Workspace CSE KACLS.
The easiest way to do this is to set an environment variable `JAVA_TOOL_OPTIONS` to `-Dfile.encoding=UTF8`.
Alternatively when starting the application you can add the encoding system property to the startup command: `java -Dfile.encoding=UTF-8 -jar flowcrypt-workspace-key-manager.jar`

## Running the application

Before you run the application, you have to set up your Master Secrets. See [generating master secrets](#section-store). 

Once your master secrets and other properties are configured, start WKM by running: `java -jar flowcrypt-workspace-key-manager.jar`

Default command is to start the server at `localhost:32567`. Other commands:

| Command | Description |
|:---------|:---------|
| `--version` | Print application version |
| `--help` | Print application help |
| `--create-master-key` | Generates Master Key and print it out if the `store.master.key.source` is either `stdin` or `properties`. If `store.master.key.source` is set to either `kmip` or `pkcs11`, the newly generated key will also be automatically stored at the configured KMIP or PKCS#11 store. This should be done one time during initial configuration.
| `--test-store-connection` | This will test that you have Master Key retrieval properly configured. It may ask for Master Key in case you set `store.master.key.source` to `stdin`. |  

Command line options:

| Argument | Default | Description |
|:---------|:---------|:------------ |
| `--config=<cfg.properties>` | `flowcrypt-workspace-key-manager.properties` | config file path |


## Configuration

The sample configuration file appropriate for your software version will come distributed along with the jar file. It consists of several sections: Common, Store, Logger, Authentication, Google Workspace, ACL. Each is described in detail below.

You will also need to set up a [CSE configuration file](#section-authenticator) containing IdP information that is publicly accessible on your domain.

 - Logger section: see [On-prem logging](https://flowcrypt.com/docs/technical/enterprise/configuration/logging.html) 
 - [On-prem High Availability and Scaling](https://flowcrypt.com/docs/technical/enterprise/configuration/high-availability-scaling.html).  
 - [Deployment checklist](https://flowcrypt.com/docs/technical/enterprise/configuration/deployment-checklist.html).


### Section: Common

See [On-prem general configuration and HTTPS](https://flowcrypt.com/docs/technical/enterprise/configuration/general-and-https.html)

### Section: Store

The WKM needs to be set up with Master Key and a Test Vector. All individual object (cloud file) keys are then derived from these master secrets on the fly. To generate your master secrets, run:

```shell
$ java -jar flowcrypt-workspace-key-manager.jar --create-master-key
```

This command will generate master key and print out the asociated test vector for you:

| Output | Description |
|:---------|:---------|
| `Master Key` | Base64 encoded 32 bytes (256 bits) random value used for key derivation. Keep this strictly secret. It is only required if `store.master.key.source` is either `stdin` or `properties`|
| `Test Vector` | Base64 encoded 32 byte (256 bit) test value encoded as Base64 that is used to verify correctness of supplied Master Key. This is especially useful when sysadmin chooses to enter secrets from stdin manually. |

| Secret retrieval option | Description |
|:---------|:---------|
| `properties` | Store the master key in the properties file |
| `stdin` | Sysadmin needs to supply the master key manually during app startup, through a command line prompt |
| `pkcs11` | Master key retrieved automatically from a pkcs11 compatible secret storage | 
| `kmip` | Master key retrieved automatically from a KMIP compatible secret storage |

Retrieval options can and should be combined. For example, for high security, you could have one secret stored over KMIP and another one supplied manually during WKM startup. On the other end of the spectrum, for ease of setup and convenience, you could supply both values in the properties file.

| Property | Example | Description |
|:---------|:---------|:------------ |
| `store.type` | `MasterKeyStore` | This is the default and recommended option. |
| `store.master.derivation.scheme` | `sha256-aes-ecb` | Derivation scheme. Current only option is `sha256-aes-ecb` which uses `AES256-ECB-ENCRYPT(key=MasterKey, data=SHA256(entry_id))` to derive individual keys from Master Key. |
| `store.master.key.source` | `stdin` | How to retrieve Master Key. Options are `properties`, `stdin`, `kmip` and `pkcs11` |
| `store.master.key.value` | (from `--create-master-key`) | (for `store.master.key.source=properties`) set if you wish to set Master Key in properties file |
| `store.test.vector.source` | `properties` | The only option - set Test Vector directly in properties file. |
| `store.test.vector.value` | (from `--create-master-key`) | This is used to cross-check entered Master Key |

If you have chosen `kmip` or `pkcs11` for any of the `source` properties, you also need to tell WKM how to connect to such store to retrieve master key.

#### KMIP integration

Our implementation is tested against the PyKMIP server. While KMIP is a vendor-agnostic protocol, implementations do vary from vendor to vendor. When planning a PoC, please allow some time for us to test against and integrate with your particular KMIP vendor.

| Property | Example | Description |
|:---------|:---------|:------------ |
| `store.kmip.hostname` | `kmipserver` | (for `store.master.key.source=kmip`) The hostname of the KMIP server. |
| `store.kmip.port` | `5696` | (for `store.master.key.source=kmip`) The listening port of the KMIP server. |
| `store.kmip.master.key.identifier` | `2085` | (for `store.master.key.source=kmip`) The unique identifier of the master key stored at KMIP server. |
| `store.kmip.master.key.name` | `flowcrypt-workspace-km-master-key` | (for `store.master.key.source=kmip`) The name of the master key stored at KMIP server. |
| `store.kmip.key.file` | `keystore.p12` | (for `store.master.key.source=kmip`) The keystore file containing the certificate to present to the KMIP server on TLS handshake. |
| `store.kmip.key.password` | `changeit` | (for `store.master.key.source=kmip`) The password to access the KMIP keystore file. |

##### KMIP Authentication

KMIP authentication works in the following way: the server (your key store/HSM) as well as the client (in this case this WKM) each have their own TLS certificates. Each certificate must be mutually trusted to establish a connection. When configuring WKM, you can use the `truststore.file` to point to a file containing trusted certificates to validate KMIP server's credentials, preventing MITM. Likewise, your KMIP server should be configured to strictly verify the client's cert.

#### PKCS#11 integration

We develop and test our implementation against Equinix SmartKey (Fortanix SDKMS). For this we used their PKCS#11 shared library module (.so), accessed through `iaik.pkcs.pkcs11.wrapper` Java library. To connect our software to your PKCS#11 HSM, update `store.pkcs11.module` to point to module provided by your HSM vendor. 

To test your pkcs module, you can use pkcs11-tool on Ubuntu 18.04:

```shell
$ sudo apt-get -y install opensc
$ pkcs11-tool --module vendor-pkcs11.so --show-info
```

Then set the following in the properties file:

| Property | Example | Description |
|:---------|:---------|:------------ |
| `store.pkcs11.module` | `./vendor-pkcs11.so` | (for `store.master.key.source=pkcs11`) Path to a pkcs#11 shared library. The library can be obtained from your HSM vendor |
| `store.pkcs11.pin` | `file://vendor-pkcs11.cfg` | (for `store.master.key.source=pkcs11`) PKCS#11 token pin. In the case of Fortanix and possibly other vendors, this is actually a path to a pkcs#11 config file |

#### Test store connection

To test that the WKM can retrieve Master Secrets and that they are valid, run:

```shell
java -jar flowcrypt-workspace-key-manager.jar --test-store-connection
```

This will validate a Test Vector to make sure the Store is properly set up. The command returns status 0 on unix systems when successful. Successful output:

```
Registering StdoutLogger as Logger implementation
INFO  Reflection - Registering MasterKeyStore as Store implementation
INFO  MasterKeyStore - Successfully validated MasterKeyStore Test Vector
INFO  c.f.keymanager.TestStoreConnection - initiating test
INFO  c.f.keymanager.TestStoreConnection - success
```

### Section: Authenticator

The authenticator component configures an OpenId Connect service which verifies non-Google issued JWTs (JSON web tokens), asserting identity of user who accesses an object.

First, you need to decide if you want to use Google as your IdP or if you want to use your own. Then you set up an OpenID Connect (OIDC) authentication app on your IdP as follows:

| IdP App property | Value |
|---|---|
| App Type | `Open ID Connect`, `OIDC`, `Web Application`, `oAuth2` (exact choice depends on your IdP) |
| Name | `FlowCrypt WKM` (customizable)
| Rectangular icon | Download from: [https://flowcrypt.com/assets/imgs/svgs/flowcrypt-logo.svg](https://flowcrypt.com/assets/imgs/svgs/flowcrypt-logo.svg) |
| Square icon | Download from: [https://flowcrypt.com/img/favicons/mstile-150x150.png](https://flowcrypt.com/img/favicons/mstile-150x150.png) |
| authorized JavaScript origins | `drive.google.com`, `docs.google.com` (more origins will be added over time as Google implements them) |
| Redirect/callback URL | `https://krahsc.google.com/callback` |
| Login URL | (if using OneLogin) leave blank |

IdP specific instructions:
 - OneLogin: `Applications` -> `Custom Connectors` -> `New Connector` -> (fill) -> `Save`. When done, follow `Applications` -> `Custom Connectors` -> (FlowCrypt WKM line) `Add App to Connector` -> `Save`. You will be redirected to `Applications` -> `FlowCrypt WKM`, where you click `SSO` in the left menu - there are the fields to put into WKM properties file: `Client ID` (put into `auth.openid.audience` and set in hosted `cse-configuration` file as both `client_id` and `audience` fields - see below), `Issuer URL V2` (put into `auth.openid.issuer`) and `V2 .well-known URL` (set in hosted `cse-configuration` file as `discovery_uri` field - see below). Make sure all of your users can access this newly created Application, using a rule/policy or other such mechanism on OneLogin.
 - Google Developer Console:  `console.developers.google.com` -> (top left project selector) -> `NEW PROJECT` -> `flowcrypt-WKM`. Next, new `OAuth Consent Screen` -> internal, add a name and logo as above, authorized domains: `google.com`. Finally, in left menu `Credentials` -> `+ CREATE CREDENTIALS` -> `OAuth Client ID` -> `Web Application` -> fill origins and redirect URI as above -> `CREATE`. You will get your `Client ID` on the next screen (client secret is not needed).   

Next, host a file at the (sub)domain associated with your Google account. If your account domain was `subdomain.domain.tld`, then host this file at: https://cse.subdomain.domain.tld/.well-known/cse-configuration with the following format:

```json
{
	"name" : "[Name of your IdP]",
	"client_id" : "[oAuth Client ID of the app requesting authentication, get this from your IdP]",
	"discovery_uri" : "[your IdP issuer path]/.well-known/openid-configuration",
	"audience" : "[the expected JWT aud claim, get this from your IdP - often same as client_id above]"
}
```

As an example, if you were to use Google as your IdP, you would set up an internal oAuth Screen web app on your Google Developer Console. Then host the following file:

```json
{
	"name" : "Google IdP",
	"client_id" : "[oAuth Client ID from Google Developer Console]",
	"discovery_uri" : "https://accounts.google.com/.well-known/openid-configuration",
	"audience" : "[same as the client_id above]"
}
```

| Property | Example | Description |
|:---------|:---------|:------------ |
| `auth.enduser.idps` | `default` | Comma separated list of Identity Providers names for standard users. |
| `auth.enduser.<idp>.issuer` | `https://accounts.google.com/` | Substitute <idp> for the IdP name above. The expected issuer of the authentication JWT token. |
| `auth.enduser.<idp>.audience` | `audience` | Substitute <idp> for the IdP name. The expected JWT token "aud" claim. If you use Google as your IdP, then this should be your oAuth Client ID. |
| `auth.enduser.<idp>.jwks` | `https://www.googleapis.com/oauth2/v3/certs` | (Optional) Substitute <idp> for the IdP name. The JWKS (JSON Web Key Set) containing the public keys to validate the authentication JWTs against. When not provided, WKM will try to poll `[issuer]/.well-known/openid-configuration` to retrieve the jwks url during startup. | 
| `auth.admin.idps` | `default` | Comma separated list of Identity Providers names for admins. |
| `auth.admin.<idp>.issuer` | `https://accounts.google.com/` | Substitute <idp> for the IdP name. The expected issuer of the authentication JWT token. |
| `auth.admin.<idp>.audience` | `audience` | Substitute <idp> for the IdP name. The expected JWT token "aud" claim. If you use Google as your IdP, then this should be your oAuth Client ID. |
| `auth.admin.<idp>.jwks` | `https://www.googleapis.com/oauth2/v3/certs` | (Optional) Substitute <idp> for the IdP name. The JWKS (JSON Web Key Set) containing the public keys to validate the authentication JWTs against. When not provided, WKM will try to poll `[issuer]/.well-known/openid-configuration` to retrieve the jwks url during startup. | 

Make sure this cse-configuration file can be accessed over CORS by browsers. For this you need to add the following CORS headers:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET
```

To verify that you have added CORS headers properly, you can use curl as follows (edit to match your path):

```shell
curl -Is https://cse.subdomain.domain.tld/.well-known/cse-configuration
```

### Section: Google Workspace

The GSuite authorization component configures the Google OpenId Connect service which verifies Google issued JWTs, making sure the user requesting access to a particular object is allowed to access it.

| Property | Example | Description |
|:---------|:---------|:------------ |
| `google.workspace.products` | `drive,meet,calendar,gmail` | Comma separated list of Google Workspace products to integrate with WKM. |
| `google.workspace.privileged.users` | `admin@org.com,admin2@org.com` | List of legal admins (different from technical admins) who may perform privileged operations on data that belongs to other users. |
| `google.workspace.kacl.account.email` | `kacl@org.com` | Google account email associated with this KACL. |
| `google.workspace.<product>.product.family` | `default` | (Optional) Google CSE product family. Options: `default`, `gmail`. Default value is `default` |
| `google.workspace.<product>.issuer` | see default properties file | Substitute <product> for the Workspace product above. The expected issuer of the authorization JWT token, this is the only accepted value. |
| `google.workspace.<product>.audience` | `cse-authorization` | Substitute <product> for the Workspace product above. This is the only accepted value. |
| `google.workspace.<product>.jwks` | see default properties file | Substitute <product> for the Workspace product above. The JWKS (JSON Web Key Set) containing the public keys to validate the authorization JWTs against. This is the only accepted value. |

### Section: ACL

The ACL component allows third party implementations further protect resources.  Please email `human@flowcrypt.com` to use a 3rd party ACL.

| Property | Example | Description |
|:---------|:---------|:------------ |
| `acl.type` | `NoThirdPartyAcl` | Currently NoThirdPartyAcl is the only ACL option. |

## Troubleshooting

Because the Google CSE combines their own systems with your existing IdP and our WKM, which in turn may rely on your KMIP or PKCS11 store, each with various configuration options, you may run into issues the first time you attempt to configure all these together.

To troubleshoot WKM startup, first see [Troubleshooting](https://flowcrypt.com/docs/technical/enterprise/configuration/general-and-https.html#Troubleshooting).

### Troubleshooting Google Alpha CSE

In this early stage of Google CSE, you may encounter unintuitive errors with no clear resulution guidance, such as the ones described below.

#### Error 404/Not Found on callback URL

If during testing you are getting a 404 when your IdP redirects to this URL after login (for example when you're uploading a new file), this can have one of the following causes:
 - (during Google Alpha) Google needs to whitelist your user or issuer
 - (during Google Alpha) You signed into several Google accounts, and the test user is not the default user on your browser. Try to log out of all accounts and only sign into the target test account. Alternatively, use Incognito mode in Chrome with only the target test account.  

#### An error occurred with the identity provider service

This can manifest as an error saying *"An error occurred with the identity provider service"*, or *"Can't decrypt file (Something went wrong and your file wasn't downloaded)"* or *"An error occurred with identity provider service"*. There are two possible causes:
 - (during Google Alpha) your browser did not yet authenticate with your IdP within drive.google.com. To authenticate during Alpha, upload a drive file first instead, go through an "Upload failure" and force re-authentication as described below. Then you can go back to your original task (opening file, updating doc, etc). 
 - your IdP is misconfigured, such as the user you are logged in with was not assigned to the IdP app, or wrong Client ID in cse-configuration, etc. To debug, you can observe the browser network tab, or ask Google.
 
#### Upload failure

You can see an "Upload failure" on drive.google.com when you are uploading an encrypted file and have not yet been authenticated on this browser. To resolve, click the exclamation mark in a red circle (!) shown with this error. This will force re-authentication.

Re-authenticating through the encrypted file upload flow will fix other authentication issues around the Drive/Docs apps that don't yet have their own robust auth error handling mechanism.

### Contact

For help or to report issues, please email `human@flowcrypt.com`.


## Sample config file

```properties
# docs:
# https://flowcrypt.com/docs/technical/workspace-key-manager/latest/workspace-key-manager.html

### General ###

org.id=evaluation.org

api.hostname=0.0.0.0
api.port=32567
api.accept.hosts=wkm.evaluation.org,localhost:32567
api.https.enabled=true
api.https.key.file=wkm-https-cert.p12
api.https.key.password=password
api.cors.origins=https://*.google.com
api.url=https://wkm.evaluation.org
#api.error.format=detailed|short|id_only
api.error.format=id_only
api.openapi.enabled=false

# Truststore is optional - if you want to override default JRE truststore
# use this to verify KMIP server with custom cert
#truststore.file=wkm-dev-rootca.p12
#truststore.password=password


### Store ###

# the options for "key.source" field is: properties | stdin | kmip | pkcs11
# the only option for "test.vector.source" is: properties
# Required key format is 32 bytes (256 bits) of random data encoded as base64
# Generate master secrets, and test vector by running: --create-master-key (uses Java SecureRandom, or KMS over KMIP)

store.type=MasterKeyStore
store.master.derivation.scheme=sha256-aes-ecb
store.master.key.source=properties
# enter "--create-master-key" output (Master Key) here to set Master Key in properties file
store.master.key.value=
store.test.vector.source=properties
# enter "--create-master-key" output (Test Vector) here either way. This is used to cross-check entered Key
store.test.vector.value=

# master key stored in secure key storage over KMIP protocol (eg Gemalto Safenet KeySecure)
# remember to also set `truststore.file` above if KMIP server uses certs with custom CA
#store.kmip.hostname=localhost
#store.kmip.port=5696
#store.kmip.key.file=localhost.p12
#store.kmip.key.password=password
#store.kmip.master.key.name=flowcrypt-workspace-km-master-key
#store.kmip.master.key.identifier=

# master key stored over PKCS#11 protocol (Fortanix SDKMS, Equinix SmartKey or any compatible HSM)
#store.pkcs11.module=./vendor-pkcs11.so
#store.pkcs11.pin=file://vendor-pkcs11.cfg


### Logger ###

# comma separated list - can have any combination of StdoutLogger, FileLogger, StackdriverLogger, SplunkHttpLogger
logger.types=StdoutLogger
# trace, debug, info, warn, error
logger.default.level=info
#logger.stdout.include.datetime=true
#logger.file.folder=/var/logs
#logger.file.history.size=14
#logger.file.history.compression=false
#logger.file.include.datetime=true
#logger.stackdriver.credentials.file=/etc/google/auth/application_default_credentials.json
#logger.splunk.url=https://splunk-instance:8088
#logger.splunk.token=327bfa46-...
#logger.splunk.disable.certificate.validation=true


### Authentication ###

# Use defaults provided below if you intend to use Google as your IdP. In that case, set up an oAuth Screen
#    on Google Developer Console, and provide oAuth Client ID in audience field.
# Else change issuer and jwks to your custom company IdP.
auth.enduser.type=OidcAuthenticator
auth.enduser.idps=default
auth.enduser.default.issuer=https://accounts.google.com
auth.enduser.default.audience=SET_YOUR_GOOGLE_OAUTH_CLIENT_ID_HERE
auth.enduser.default.jwks=https://www.googleapis.com/oauth2/v3/certs

auth.admin.type=OidcAuthenticator
auth.admin.idps=default
auth.admin.default.issuer=https://accounts.google.com
auth.admin.default.audience=SET_YOUR_GOOGLE_OAUTH_CLIENT_ID_HERE
auth.admin.default.jwks=https://www.googleapis.com/oauth2/v3/certs

### Google Workspace Products ###
google.workspace.products=drive,meet,calendar,gmail
google.workspace.privileged.users=
google.workspace.kacl.account.email=

### Google Workspace Authorization (Docs & Drive) ###
google.workspace.drive.product.family=default
google.workspace.drive.issuer=gsuitecse-tokenissuer-drive@system.gserviceaccount.com
google.workspace.drive.audience=cse-authorization
google.workspace.drive.jwks=https://www.googleapis.com/service_accounts/v1/jwk/gsuitecse-tokenissuer-drive@system.gserviceaccount.com

### Google Workspace Authorization (Meet) ###
google.workspace.meet.product.family=default
google.workspace.meet.issuer=gsuitecse-tokenissuer-meet@system.gserviceaccount.com
google.workspace.meet.audience=cse-authorization
google.workspace.meet.jwks=https://www.googleapis.com/service_accounts/v1/jwk/gsuitecse-tokenissuer-meet@system.gserviceaccount.com

### Google Workspace Authorization (Calendar) ###
google.workspace.calendar.product.family=default
google.workspace.calendar.issuer=gsuitecse-tokenissuer-calendar@system.gserviceaccount.com
google.workspace.calendar.audience=cse-authorization
google.workspace.calendar.jwks=https://www.googleapis.com/service_accounts/v1/jwk/gsuitecse-tokenissuer-calendar@system.gserviceaccount.com

### Google Workspace Authorization (Gmail) ###
google.workspace.gmail.product.family=gmail
google.workspace.gmail.issuer=gsuitecse-tokenissuer-gmail@system.gserviceaccount.com
google.workspace.gmail.audience=cse-authorization
google.workspace.gmail.jwks=https://www.googleapis.com/service_accounts/v1/jwk/gsuitecse-tokenissuer-gmail@system.gserviceaccount.com

### ACL ###

acl.type=NoThirdPartyAcl

```
