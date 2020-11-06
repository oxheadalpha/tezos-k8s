from distutils.core import setup

setup(
    name="mkchain",
    version="0.1",
    packages=["tqchain"],
    include_package_data=True,
    install_requires=["pyyaml"],
    entry_points={"console_scripts": ["mkchain=tqchain.mkchain:main"]},
)
