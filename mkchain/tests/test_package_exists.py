def test_package_exists() -> None:
    import tqchain

    assert vars(tqchain)["__name__"] == "tqchain"
