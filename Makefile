-include .env

.PHONY: all test clean deploy-all


all:  clean build test deploy-all

# Clean the repo
clean  :; forge clean

update:; forge update

build:; forge build

test :; forge test -vvvvv

format:; forge fmt

# Remove modules
# remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts

deploy:; @forge script script/vault.s.sol:VaultScript --rpc-url ${MUMBAI_RPC_URL} --private-key ${PRIVATE_KEY} --broadcast --verify -vvvv
