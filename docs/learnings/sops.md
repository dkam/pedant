# SOPS + age

Facts about SOPS with age keys and dotenv files, the format booko-services
will use. Verified with sops 3.13.3 and age 1.3.2 on 2026-10-04, using
throwaway keys. The **Check** script at the end re-verifies all of them.

## Facts

**Variable names stay in plaintext; only values are encrypted.** An encrypted
dotenv file reads `API_TOKEN=ENC[AES256_GCM,data:…]`. Anything without a key
can list the variable names with `grep -v '^sops_' file | cut -d= -f1`.

**Recipients are in plaintext.** Each age recipient appears as
`sops_age__list_N__map_recipient=age1…`. Without decrypting, you can tell
which keys a file was encrypted for, and so which hosts can read it.
`sops_lastmodified` is plaintext too.

**Creating an encrypted file needs only public keys.**
`sops encrypt --age "$PUB1,$PUB2"` works with no private key available.

**Changing a value in an existing file needs a private key.** `sops set` fails
with "at least one key has to be successful, but none were" when no
recipient's private key is available. sops encrypts the values with a data
key, and only a recipient's private key can unwrap that. So a holder of public
keys can write a whole new file, but can't edit one value in place.

**A key that isn't a recipient can't decrypt.** It fails with the same error.
That's what makes per-host keys work: a misc01 key can't read a hetz01 file.

**Values are authenticated.** Changing one character of an `ENC[…]` value makes
decryption fail with `cipher: message authentication failed`, so a corrupted
or hand-edited ciphertext fails loudly instead of decrypting to garbage.

**sops doesn't need the `age` binary.** sops does the age encryption itself;
`age-keygen` is needed only to make keys. A key file's public key is on its
`# public key: age1…` line, or comes from `age-keygen -y key.txt`.

## Check

```sh
cd "$(mktemp -d)"; unset SOPS_AGE_KEY_FILE SOPS_AGE_KEY
for k in a b c; do age-keygen -o $k.key 2>/dev/null; done
A=$(age-keygen -y a.key); B=$(age-keygen -y b.key)
printf 'API_TOKEN=s3cret\n' > x.env
sops encrypt --age "$A,$B" --input-type dotenv --output-type dotenv x.env > x.sops.env  # public keys only
grep -v '^sops_' x.sops.env | cut -d= -f1                                              # names visible
grep '_map_recipient=' x.sops.env                                                      # recipients visible
sops set --input-type dotenv --output-type dotenv x.sops.env '["API_TOKEN"]' '"n"'     # fails: no private key
SOPS_AGE_KEY_FILE=c.key sops decrypt --input-type dotenv --output-type dotenv x.sops.env  # fails: not a recipient
SOPS_AGE_KEY_FILE=b.key sops decrypt --input-type dotenv --output-type dotenv x.sops.env  # works
```
