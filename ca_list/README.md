# ca\_list

This tool uses the certificates gathered by monitoring to create a simple list of organizations connected to eduroam along with current CA that issues the EAP cert and names of the servers.
This is meant as a fallback solution for users that want to use their devices securely but for some reasons they are not able to use eduroam CAT.

## how to use

The resulting output is in the dokuwiki format.
To generate the output, just simply run:

```
./get_info.sh | ./ca_list.py > output.dokuwiki
```

## links to known CAs

To help users get info about the CAs, list of known CAs is available in `cert_db.py`. Links for CA names which are configured in this file are generated in the output file instead of CA names.

## TODO

- direct links download the CAs that issued the EAP certs?
- git repo of the CAs to display additional info if the CA changes?

