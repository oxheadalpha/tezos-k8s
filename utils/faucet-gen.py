#! /usr/bin/env python
# This script creates faucet accounts for testnets.
# Generation is deterministic based on the seed passed.
# This allows deployment of faucet infrastructure without moving
# large json commitment files around.

import sys
import os
import json
import bitcoin
import binascii
import numpy as np
import pysodium
from pyblake2 import blake2b
import unicodedata
from hashlib import sha256
import random
import string

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
    amounts = np.random.pareto(10.0, n)
    amounts = amounts / sum(amounts) * 700e6
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

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: faucet-gen.py seed [number_of_accounts]")
        exit(1)
    print(f"Seed is {sys.argv[1]}")
    blind = sys.argv[1].encode('utf-8')
    if len(sys.argv) == 3:
        number_of_accounts = int(sys.argv[2])
    else:
        number_of_accounts = 2
    # initialize random functions for determinism
    random.seed(a=blind, version=2)
    numpy_seed = random.randint(0,2**32)
    print("numpy seed is %s" % numpy_seed)
    np.random.seed(seed=numpy_seed)
    wallets, secrets = make_dummy_wallets(number_of_accounts, blind)

    commitments = genesis_commitments(wallets, blind)

    with open('./faucet-commitments/commitments.json', 'w') as f:
        json.dump([
                (commitment['blinded_pkh'], str(commitment['amount']))
                for commitment in commitments if commitment['amount'] > 0
            ], f, indent=1)
