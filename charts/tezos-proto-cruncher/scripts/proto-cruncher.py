import hashlib
import locale
import os
import random
import re
import string
import sys
import time

from multiprocessing import Pool
from multiprocessing.pool import ThreadPool

if os.getenv("FORCE_PY_BASE58"):
    import base58
else:
    try:
        import based58 as base58

        print(f"Using based58 from {base58.__file__}")
    except:
        print(
            """
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        Unable to import based58, will fall back to slow "base58"
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        """
        )
        import base58

proto_file = sys.argv[1]


def tb(l):
    return b"".join(map(lambda x: x.to_bytes(1, "big"), l))


proto_prefix = tb([2, 170])

PROTO_NAME = os.getenv("PROTO_NAME")
VANITY_STRING = os.getenv("VANITY_STRING")
NUM_NONCE_DIGITS = int(os.getenv("NUM_NONCE_DIGITS", 16))
BUCKET_NAME = os.getenv("BUCKET_NAME")
BUCKET_ENDPOINT_URL = os.getenv("BUCKET_ENDPOINT_URL")
BUCKET_REGION = os.getenv("BUCKET_REGION")
EXACT_MATCH = os.getenv("EXACT_MATCH")

if not VANITY_STRING:
    raise ValueError("VANITY_STRING env var must be set")


def capitalization_permutations(s):
    """Generates the different ways of capitalizing the letters in
    the string s.

    >>> list(capitalization_permutations('abc'))
    ['ABC', 'aBC', 'AbC', 'abC', 'ABc', 'aBc', 'Abc', 'abc']
    >>> list(capitalization_permutations(''))
    ['']
    >>> list(capitalization_permutations('X*Y'))
    ['X*Y', 'x*Y', 'X*y', 'x*y']
    """
    if s == "":
        yield ""
        return
    for rest in capitalization_permutations(s[1:]):
        yield s[0].upper() + rest
        if s[0].upper() != s[0].lower():
            yield s[0].lower() + rest


vanity_bytes = VANITY_STRING.encode("ascii")
vanity_length = len(vanity_bytes)


def is_vanity_exact(new_hash):
    return new_hash[:vanity_length] == vanity_bytes


# leave first two chars - prefix - alone, but do case permutations for the rest
vanity_set = {
    (VANITY_STRING[:2] + p).encode("ascii")
    for p in capitalization_permutations(VANITY_STRING[2:])
}


def is_vanity_ignore_case(new_hash):
    return new_hash[:vanity_length] in vanity_set


if EXACT_MATCH:
    is_vanity = is_vanity_exact
else:
    print("Vanity set:", vanity_set)
    is_vanity = is_vanity_ignore_case


if BUCKET_NAME:
    import boto3

    s3 = boto3.resource(
        "s3", region_name=BUCKET_REGION, endpoint_url=f"https://{BUCKET_ENDPOINT_URL}"
    )

with open(proto_file, "rb") as f:
    proto_bytes = f.read()

with open(proto_file, "rb") as f:
    proto_lines = f.readlines()


# For speed, we precompute the hash of the proto without the last line
# containing the vanity nonce.
# Later on, we add the last line and recompute.
# This speeds up the brute force by a large factor, compared to hashing
# in full at every try.
original_nonce = proto_lines[-1]
# First 4 bytes are truncated (not used in proto hashing)
proto_hash = hashlib.blake2b(proto_bytes[4:][: -len(original_nonce)], digest_size=32)


def get_hash(vanity_nonce, proto_hash):
    proto_hash.update(vanity_nonce)
    return base58.b58encode_check(proto_prefix + proto_hash.digest()).decode("utf-8")


print(
    f"Original proto nonce: {original_nonce} and hash: {get_hash(original_nonce, proto_hash.copy())}"
)


def mk_nonce_digits():
    return "".join(random.choice(string.digits) for _ in range(NUM_NONCE_DIGITS))


def mk_new_nonce():
    new_nonce_digits = mk_nonce_digits()
    new_nonce = b"(* Vanity nonce: " + bytes(new_nonce_digits, "utf-8") + b" *)\n"
    return new_nonce


def find_vanity():

    T0 = t0 = time.time()
    count = 0
    total_count = 0
    while True:
        new_nonce = mk_new_nonce()
        new_hash = get_hash(new_nonce, proto_hash.copy())
        count += 1
        if re.match(f"^{VANITY_STRING}.*", new_hash):
            total_count = handle_result(
                (new_nonce, new_hash.encode("ascii"), count), T0, t0, total_count
            )
            t0 = time.time()
            count = 0


TEN_POWER_NUM_NONCE_DIGITS = 10**NUM_NONCE_DIGITS
NONCE_DIGITS_FMT = "{0:0%s}" % NUM_NONCE_DIGITS


def mk_nonce_digits2():
    return NONCE_DIGITS_FMT.format(random.randint(1, TEN_POWER_NUM_NONCE_DIGITS))


def mk_new_nonce2() -> bytes:
    new_nonce_digits = mk_nonce_digits2()
    new_nonce = f"(* Vanity nonce: {new_nonce_digits} *)\n".encode("ascii")
    return new_nonce


def get_hash2(vanity_nonce, proto_hash) -> bytes:
    proto_hash.update(vanity_nonce)
    return base58.b58encode_check(proto_prefix + proto_hash.digest())


def nonce_gen():
    while True:
        yield mk_new_nonce2()


def vanity_gen():
    count = 0
    for new_nonce in nonce_gen():
        count += 1
        new_hash = get_hash2(new_nonce, proto_hash.copy())
        if is_vanity(new_hash):
            yield new_nonce, new_hash, count
            count = 0


# so that "n" formatter prints large numbers with group separator
locale.setlocale(locale.LC_ALL, "")


global_stats = {"start_time": time.time(), "vanity_count": 0}


def handle_result(
    result: tuple[bytes, bytes, int], T0: float, t0: float, total_count: int
):
    new_nonce, new_hash, count = result
    dt = time.time() - t0
    total_count += count
    total_time = time.time() - T0
    hash_per_s = round(count / dt)
    avg_hash_per_s = round(total_count / total_time)
    global_stats["vanity_count"] = global_stats["vanity_count"] + 1
    print(
        f"Found: {new_nonce} -> {new_hash} in {dt:.2f} "
        f"[{count:n} tries at {hash_per_s:n} hash/s, avg {avg_hash_per_s:n} hash/s]"
    )
    if BUCKET_NAME:
        try:
            s3.Object(BUCKET_NAME, f"{PROTO_NAME}_{new_hash}").put(Body=new_nonce)
        except:
            print("ERROR: upload of the nonce and hash to s3 failed.")
    return total_count


def find_vanity2():
    T0 = t0 = time.time()
    total_count = 0
    for result in vanity_gen():
        total_count = handle_result(result, T0, t0, total_count)
        t0 = time.time()


def find_vanity_task(*_args):
    for result in vanity_gen():
        return result


def find_vanity_concurrent(use_threads=False, procs=None):
    def constant_gen():
        while True:
            yield b""

    PoolImpl = ThreadPool if use_threads else Pool

    with PoolImpl(processes=procs) as pool:
        T0 = t0 = time.time()
        total_count = 0

        for result in pool.imap_unordered(find_vanity_task, constant_gen()):
            if result:
                total_count = handle_result(result, T0, t0, total_count)
                t0 = time.time()


def print_global_stats():
    elapsed = time.time() - global_stats["start_time"]
    count = global_stats["vanity_count"]
    print(
        f"Elapsed: {elapsed}\n"
        f"Hashes found: {global_stats['vanity_count']}\n"
        f"Rate: {count/(elapsed/60.0)} per minute"
    )


def main():
    print(
        """
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        Warning - assuming the nonce is 16 chars in the original proto.
        If it is not, make sure to set NUM_NONCE_DIGITS to the right number
        otherwise you will get bad nonces.
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        """
    )
    impl = os.getenv("IMPL", "singlethread")
    procs = os.getenv("NPROCS", None)
    try:
        if procs:
            procs = int(procs)
        if impl == "multiproc":
            find_vanity_concurrent(use_threads=False, procs=procs)
        elif impl == "multithread":
            find_vanity_concurrent(use_threads=True, procs=procs)
        elif impl == "original":
            find_vanity()
        elif impl == "singlethread":
            find_vanity2()
        else:
            raise SystemExit(f"Unknown impl requested: {impl}")
    except KeyboardInterrupt:
        print_global_stats()
        raise SystemExit("keyboard interrupt")


if __name__ == "__main__":
    main()
