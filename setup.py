from setuptools import setup

setup(
    name="mkchain",
    version="0.1",
    install_requires=['pyyaml'],
    entry_points={'console_scripts': [
                      'mkchain=mkchain:main']}

)
