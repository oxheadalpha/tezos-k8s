#! /usr/bin/env python
# This script creates faucet accounts for testnets.
# Generation is deterministic based on the seed passed.
# This allows deployment of faucet infrastructure without moving
# large json commitment files around.
# Use `--write-commitments-to` to generate the public tezos address
# precursors to include in the chain activation parameters.
# This list is not sensitive.
# Use `--write-secret-seeds-to` to dump the list of private keys
# for actually running the faucet. This list is sensitive.
# `--write-secret-seeds-to` also queries every faucet account balance
# in order until it finds EMPTY_ACCOUNT_BUFFER empty addresses.
# This way, it does not need persistence. We infer from the chain
# which is the last faucet account that has been given. The ones after
# that are written in the secret json file.

import argparse
import sys
import os
import json
import bitcoin
import binascii
import pysodium
from pyblake2 import blake2b
import unicodedata
from hashlib import sha256
import random
import requests
import string

EMPTY_ACCOUNT_BUFFER = 10

def get_keys(mnemonic, email, password):
    salt = unicodedata.normalize(
    "NFKD", (email + password))
    seed = bitcoin.mnemonic_to_seed(mnemonic.encode('utf-8'), salt.encode('utf-8'))
    pk, sk = pysodium.crypto_sign_seed_keypair(seed[0:32])
    pkh = blake2b(pk,20).digest()
    pkhb58 = bitcoin.bin_to_b58check(pkh, magicbyte=434591)
    return (sk, pk, pkh, pkhb58)

def random_email():
    rnd = lambda n: ''.join(random.choice(string.ascii_lowercase) for _ in range(n))
    return '%s.%s@teztnets.xyz' % (rnd(8),rnd(8))

def tez_to_int(amount):
    return int(round(amount * 1e6, 0))

def secret_code(pkh, blind):
    return blake2b(pkh, 20, key=blind).digest()

def genesis_commitments(wallets, blind):
    commitments = []
    for pkh_b58, amount in wallets.items():
        # Public key hash corresponding to this Tezos address.
        pkh = bitcoin.b58check_to_bin(pkh_b58)[2:]
        # The redemption code is unique to the public key hash and deterministically
        # constructed using a secret blinding value.
        secret = secret_code(pkh, blind)
        # The redemption code is used to blind the pkh
        blinded_pkh = blake2b(pkh, 20, key=secret).digest()
        commitment = {
            'blinded_pkh': bitcoin.bin_to_b58check(blinded_pkh, magicbyte=16921055),
            'amount': amount
        }
        commitments.append(commitment)
    return commitments

# Generate dummy genesis information for a centralized alphanet faucet
def make_dummy_wallets(n, blind):
    # Not a realistic shape, but for an alphanet faucet it's better to
    # have less variance.
    amounts = [ random.paretovariate(10.0) - 1 for i in range(n) ]
    amounts = [ i / sum(amounts) * 700e6 for i in amounts ]
    wallets = {}
    secrets = {}
    for i in range(0, n):
        entropy = blake2b(str(i).encode('utf-8'), 20, key=blind).digest()
        mnemonic = bitcoin.mnemonic.entropy_to_words(entropy)
        password = ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(10))
        email    = random_email()
        sk, pk, pkh, pkh_b58 = get_keys(' '.join(mnemonic), email, password)
        amount = tez_to_int(amounts[i])
        wallets[pkh_b58] = amount
        secret = secret_code(pkh, blind)
        secrets[pkh_b58] = (mnemonic, email, password, amount, binascii.hexlify(secret))
    return wallets, secrets

parser = argparse.ArgumentParser()
parser.add_argument("--seed", help="a seed for deterministic faucet gen",
                            type=str)
parser.add_argument("--number-of-accounts", help="number of faucet accounts to generate",
                            type=int)
parser.add_argument("--write-commitments-to", help="file path where to write the public commitments (typically for chain activation)",
                            type=str)
parser.add_argument("--write-secret-seeds-to", help="file path where to write the secret seed file (typically for launching a faucet)",
                            type=str)
args = parser.parse_args()

if __name__ == '__main__':
    print(f"Seed is {args.seed}")
    blind = args.seed.encode('utf-8')
    # initialize random functions for determinism
    random.seed(a=blind, version=2)
    wallets, secrets = make_dummy_wallets(args.number_of_accounts, blind)

    commitments = genesis_commitments(wallets, blind)

    if args.write_commitments_to:
        with open(args.write_commitments_to, 'w') as f:
            json.dump([
                    (commitment['blinded_pkh'], str(commitment['amount']))
                    for commitment in commitments if commitment['amount'] > 0
                ], f, indent=1)

    if args.write_secret_seeds_to:
        print("Searching for already used faucet keys")
        print(f"Assuming that if we see more than {EMPTY_ACCOUNT_BUFFER} empty accounts, we have reached the end of the faucet")
        print(f"Hopefully it's true. But if someone claims more than {EMPTY_ACCOUNT_BUFFER} faucets and do not use them, then our assumption is wrong")
        faucet_pkhs = secrets.keys()
        balances = {}
        # TODO wait for bootstrap
        for i, pkh in enumerate(faucet_pkhs):
            balances[pkh] = int(requests.get("http://tezos-node-rpc:8732/chains/main/blocks/head/context/contracts/%s/balance" % pkh).json())
            print(f"Balance for {pkh} is {balances[pkh]}")
            if i >= EMPTY_ACCOUNT_BUFFER and set([ balances[pkh] for pkh in list(faucet_pkhs)[i - EMPTY_ACCOUNT_BUFFER:i] ]) == { 0 }:
                # 10 past accounts are empty, assuming we have reached the end of the used faucets
                print(f"Found the first empty faucet address: {list(faucet_pkhs)[i-10]}")
                break
        unused_secrets = { pkh: secrets[pkh] for pkh in list(faucet_pkhs)[i-10:] }

        with open(args.write_secret_seeds_to, 'w') as f:
            json.dump([ { "pkh" : pkh,
                          "mnemonic" : mnemonic,
                          "email" : email,
                          "password" : password,
                          "amount" : str(amount),
                          "activation_code" : secret.decode('utf-8') }
                        for pkh, (mnemonic, email, password, amount, secret) in unused_secrets.items()], f, indent=1)
