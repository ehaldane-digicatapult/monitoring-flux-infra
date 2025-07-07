#!/usr/bin/env bash

# sanitise environment.
# Check for presense of sensible version of kind, kubectl, flux
# check for GITHUB_TOKEN env variable

# check for valid cluster without flux installed
# install flux on the cluster
# creates the flux-system git source resource on the cluster
# creates the flux-system kustomization on the cluster

INFRA_GIT=https://github.com/ehaldane-digicatapult/monitoring-flux-infra/
INFRA_BRANCH=main
CONTEXT_NAME=kind-monitoring-flux-infra
INFRA_BASE_PATH=./examples/kind/base


print_usage() {
  echo "Installs flux onto a cluster and sets up the git sources and kustomizations necessary to get started"
  echo ""
  echo "Usage:"
  echo "  ./scripts/install-flux.sh [ -h ] [ -g <git_repository> ] [ -b <base_branch> ] [ -c <kind_context_name> ] [ -p <base_path> ]"
  echo ""
  echo "Options:"
  echo "  -g        Specify an alternative git repository. Note the default assumes http authentication"
  echo "            (default: https://github.com/ehaldane-digicatapult/monitoring-flux-infra/)"
  echo "  -b        Specify an alternative base branch to use."
  echo "            (default: main)"
  echo "  -c        Specify the context name of your cluster"
  echo "            (default: kind-monitoring-flux-infra)"
  echo "  -p        Specify an alternative base path"
  echo "            (default: ./examples/kind/base)"
  echo ""
  echo "Flags: "
  echo "  -h        Prints this message"
}

while getopts ":g:b:c::p:h" opt; do
  case ${opt} in
    h )
      print_usage
      exit 0
      ;;
    g )
      INFRA_GIT=${OPTARG}
      ;;
    b )
      INFRA_BRANCH=${OPTARG}
      ;;
    c )
      CONTEXT_NAME=${OPTARG}
      ;;
    p )
      INFRA_BASE_PATH=${OPTARG}
      ;;
   \? )
     echo "Invalid Option: -$OPTARG" 1>&2
     echo "\n"
     print_usage
     exit 1
     ;;
  esac
done

assert_command() {
  local command=$1

  printf "Checking for presense of $command..."
  local path_to_executable=$(command -v ${command})

  if [ -z "$path_to_executable" ] ; then
    echo -e "Cannot find ${command} executable. Is it on your \$PATH?"
    exit 1
  fi
  printf "OK\n"
}

assert_env() {
  local context=$1

  # check that GITHUB_TOKEN env variable is set
  printf "Checking for presense of GITHUB_TOKEN environment variable..."
  if [[ -z "$GITHUB_TOKEN" ]]; then
    printf "NOT OK\nGithub token env variable is empty or not set.  Please set a valid GITHUB_TOKEN environment variable.\n"
    exit 1
  fi
  printf "OK\n"

  # first check that cluster actually exists
  printf "Checking for presense of context $context..."
  kubectl cluster-info --context $context &> /dev/null
  local ret=$?
  if [ "$ret" -ne 0 ]; then
    printf "NOT OK\nError accessing kind cluster $context. Have you created the kind cluster?\n"
    exit 1
  fi
  printf "OK\nCluster $context exists\n"
}

assert_flux_env() {
    printf "Checking if flux is currently installed..."
    kubectl get namespaces flux-system &> /dev/null
    local ret=$?
    if [ "$ret" -eq 0 ]; then
        printf "OK\nFlux is currently installed, will attempt to upgrade\n"
    elif [ "$ret" -ne 0 ]; then
        printf "OK\nFlux is not installed, will attempt to install\n"
    fi
}

install_flux() {
    local context=$1
    printf "Installing Flux...\n"
    flux install --context $context --timeout=3m
    local ret=$?
    if [ "$ret" -eq 0 ]; then
      printf "OK\nFlux successfully installed in $context\n"
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\nFlux failed to install in $context\n"
        printf "Try seeing which pods failed using \"kubectl get pods -n flux-system\"\n"
        exit 1
    fi
}

setup_flux_git_source() {
    local context=$1
    local repo=$2
    local branch=$3
    printf "Creating Git source from $repo on branch $branch in flux $context...\n"
    flux create source git --context=$context --interval=1m --namespace=flux-system --branch=$branch --url=$repo flux-system
    local ret=$?
    if [ "$ret" -eq 0 ]; then
      printf "OK\nGit Source \"flux-system\" successfully installed in $context\n"
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\nGit Source \"flux-system\" failed to install in $context\n"
        exit 1
    fi
}

setup_flux_kustomization() {
    local context=$1
    local path=$2
    printf "Creating kustomization from $path in $context...\n"
    flux create kustomization --context=$context --interval=10m --namespace=flux-system --path=$path --prune --source=flux-system --validation=client flux-system
    local ret=$?
    if [ "$ret" -eq 0 ]; then
      printf "OK\nKustomization \"flux-system\" successfully installed in $context\n"
    elif [ "$ret" -ne 0 ]; then
        printf "ERROR\nKustomization \"flux-system\" failed to install in $context\n"
        exit 1
    fi
}

assert_command kubectl
assert_command flux
assert_env $CONTEXT_NAME
assert_flux_env $CONTEXT_NAME
install_flux $CONTEXT_NAME
setup_flux_git_source $CONTEXT_NAME $INFRA_GIT $INFRA_BRANCH
setup_flux_kustomization $CONTEXT_NAME $INFRA_BASE_PATH
