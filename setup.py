from setuptools import setup

setup(
    name="mkchain",
    version="0.1",
    py_modules=['mkchain'],
    install_requires=["pyyaml", "kubernetes"],
    entry_points={"console_scripts": ["mkchain=mkchain:main"]},
)
