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


## sample output

Output is in the dokuwiki format for ease of direct inclusion in the wiki.

```
^ organizace ^ realmy ^ použitá CA ^ jména RADIUS serverů ^
| [[https://www.5zskadan.cz/index.php?type=Post&id=224&ids=120|Základní škola Kadaň]] | @5zskadan.cz | [[https://www.eduroam.cz/cs/spravce/pripojovani/eduroamca|eduroam CA]] | radius1.5zskadan.cz |
| [[http://www.rowanet.cz/moduly/eduroam_fw.php?detail_cs=87|Střední soukromá škola Lesnická s.r.o.]] | @agro-skola.cz | agroskola-WINSRV01-CA | eduroam.kr-vysocina.cz |
| [[http://www.hotelova-skola-plzen.cz/pristup-do-site-eduraoam|Akademie hotelnictví a cestovního ruchu]] | @akademie-hotelnictvi.cz | GeoTrust Primary Certification Authority - G3 | radius.akademie-hotelnictvi.cz |
| [[http://eduroam.alga.cz/index.php|Mikrobiologický ústav AV ČR]] | @alga.cz | DST Root CA X3 | mbu-fs.alga.cz |
| [[https://navody.amu.cz/eduroam-cs.html|Akademie múzických umění v Praze]] | @amu.cz | [[https://www.digicert.com/digicert-root-certificates.htm|DigiCert High Assurance EV Root CA]] | radius.amu.cz |
| [[http://radius2.arub.cz/eduroam/index.html|Archeologický ústav Akademie věd České republiky, Brno, v. v. i.]] | @arub.cz | [[https://pki.cesnet.cz/cs/ch-tcs-ssl-ca-3-crt-crl.html|TERENA SSL CA 3]] | radius1.arub.avcr.cz, radius2.arub.avcr.cz |
| [[http://www.arup.cas.cz/eduroam_cs.html|Archeologický ústav Akademie věd České Republiky, Praha, v. v. i.]] | @arup.cas.cz | [[https://pki.cesnet.cz/cs/ch-tcs-ssl-ca-3-crt-crl.html|TERENA SSL CA 3]] | slon.arup.cas.cz |
| [[http://eduroam.asu.cas.cz/index.html|Astronomický ústav AV ČR, v.v.i.]] | @asu.cas.cz | [[https://pki.cesnet.cz/cs/ch-tcs-ssl-ca-3-crt-crl.html|DigiCert Assured ID Root CA]] | radius1.asu.cas.cz, radius2.asu.cas.cz |
| [[https://navody.asuch.cas.cz/doku.php/eduroam|Ústav chemických procesů AV ČR, v.v.i.]] | @asuch.cas.cz, @icpf.cas.cz | [[https://pki.cesnet.cz/cs/ch-tcs-ssl-ca-3-crt-crl.html|TERENA SSL CA 3]] | radius1.asuch.cas.cz, radius2.asuch.cas.cz |

```

## TODO

- direct links download the CAs that issued the EAP certs?
- git repo of the CAs to display additional info if the CA changes?

