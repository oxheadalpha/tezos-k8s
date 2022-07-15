# Tezos-k8s documentation

Hosted at https://tezos-k8s.xyz

The documentation is built from static markdown files in the `docs` directory as well as some generated documentation from `charts/tezos/values.yaml`.

To generate the files:

```
cd docs/
./values_to_doc.sh
```

To render locally:

```
npm install
npm run build
npm start
```
