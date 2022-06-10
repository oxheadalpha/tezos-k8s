# Signers

Define remote signers. Bakers automatically use signers in their namespace
that are configured to sign for the accounts they are baking for.

By default no signer is configured:
```
signers: {}
```
Here is an example of octez signer config. When set, the 
```
signers:
 tezos-signer-0:
   sign_for_accounts:
   - baker0
```
