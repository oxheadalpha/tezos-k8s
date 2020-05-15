# tezos-k8s
configuration files to deploy tezos on kubernetes

python3 -m venv .venv
source .venv/bin/activate
pip install -e ./

mkchain --create --stdout --baker $chain_name $cluster | kubectl apply -f -

chain_name: is your private chain's name
cluster: one of [minikube, docker-desktop]
