import random
import string
import subprocess

use_docker = False

try:
    from secrets import token_bytes

    from pytezos import pytezos
    from pytezos.crypto.encoding import base58_encode
except (ImportError, NotImplementedError):
    use_docker = True


def set_use_docker(b):
    global use_docker
    if b != None:
        use_docker = b


loaded_images = {}


def pull_docker_image(image):
    if image not in loaded_images:
        loaded_images[image] = 1
        print(f"Checking for docker image {image}")
        has_image_return_code = subprocess.run(
            f"docker inspect --type=image {image} > /dev/null 2>&1", shell=True
        ).returncode
        if has_image_return_code != 0:
            print(f"Pulling docker image {image}")
            subprocess.check_output(
                f"docker pull {image}", shell=True, stderr=subprocess.STDOUT
            )
            print(f"Done pulling docker image {image}")


def run_docker(image, entrypoint, *args):
    # We pull the image separately and before the "docker run" to
    # simplify parsing the output.  If we didn't, then "docker run"
    # might pull the image and emit the fact that it did so.
    pull_docker_image(image)
    return subprocess.check_output(
        "docker run --entrypoint %s --rm %s %s" % (entrypoint, image, " ".join(args)),
        stderr=subprocess.STDOUT,
        shell=True,
    )


def extract_key(keys, index: int) -> bytes:
    return keys[index].split(b":")[index].strip().decode("ascii")


def gen_key(image):
    if not use_docker:
        key = pytezos.key.generate(export=False)
        return {"public": key.public_key(), "secret": key.secret_key()}

    keys = run_docker(
        image,
        "sh",
        "-c",
        "'/usr/local/bin/tezos-client "
        + "--protocol PsDELPH1Kxsx gen keys mykey && "
        + "/usr/local/bin/tezos-client "
        + "--protocol PsDELPH1Kxsx show address mykey -S'",
    ).split(b"\n")

    return {"public": extract_key(keys, 1), "secret": extract_key(keys, 2)}


def get_genesis_vanity_chain_id(seed_len=16):
    print("Generating vanity chain id")

    if not use_docker:
        return base58_encode(token_bytes(32), b"B").decode("utf-8")

    seed = "".join(
        random.choice(string.ascii_uppercase + string.digits) for _ in range(seed_len)
    )

    return (
        run_docker(
            "registry.gitlab.com/tezos/flextesa:01e3f596-run",
            "flextesa",
            "vani",
            '""',
            "--seed",
            seed,
            "--first",
            "--machine-readable",
            "csv",
        )
        .decode("utf-8")
        .split(",")[1]
    )
