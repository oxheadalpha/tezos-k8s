from distutils.core import setup

setup(
    name="mkchain",
    version="0.1",
    packages=['tqchain'],
    package_data={'tqchain': ['deployment/*']},
    install_requires=["pyyaml", "kubernetes"],
    entry_points={"console_scripts": ["mkchain=tqchain.mkchain:main"]},
)
