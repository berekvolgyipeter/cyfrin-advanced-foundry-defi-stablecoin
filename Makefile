-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

# ---------- anvil constants ----------
PRIVATE_KEY_ANVIL_0 := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC_URL_ANVIL := http://localhost:8545

# ---------- dependencies ----------
uninstall :; rm -rf dependencies/ && rm soldeer.lock
install :; forge soldeer install
update:; forge soldeer update

# ---------- build ----------
build :; forge build
clean :; forge clean && rm -rf cache/

# ---------- tests ----------
TEST := forge test -vvv
TEST_UNIT := $(TEST) --match-path "test/unit/*.t.sol"

test :; $(TEST)
test-unit :; $(TEST_UNIT)
test-unit-fork-sepolia :; $(TEST_UNIT) --fork-url $(RPC_URL_SEPOLIA)
test-unit-fork-mainnet :; $(TEST_UNIT) --fork-url $(RPC_URL_MAINNET)
test-fuzz :; $(TEST) --match-path "test/fuzz/*.t.sol"
test-invariant :; $(TEST) --match-path "test/invariant/*.t.sol"
test-fork-sepolia :; $(TEST) --fork-url $(RPC_URL_SEPOLIA)
test-fork-mainnet :; $(TEST) --fork-url $(RPC_URL_MAINNET)

# ---------- coverage ----------
COVERAGE := forge coverage --no-match-test invariant --no-match-coverage "^(test|script)/"

coverage :; $(COVERAGE)
coverage-lcov :; $(COVERAGE) --report lcov
coverage-txt :; $(COVERAGE) --report debug > coverage.txt

# ---------- gas ----------
snapshot :; forge snapshot --no-match-test invariant

# ---------- static analysis ----------
lint :; forge fmt --check
slither-install :; python3 -m pip install slither-analyzer
slither :; slither . --config-file slither.config.json --checklist

# ---------- etherscan ----------
check-etherscan-api:
	@response_mainnet=$$(curl -s "https://api.etherscan.io/api?module=account&action=balance&address=$(ADDRESS_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Mainnet:" $$response_mainnet; \
	response_sepolia=$$(curl -s "https://api-sepolia.etherscan.io/api?module=account&action=balance&address=$(ADDRESS_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Sepolia:" $$response_sepolia;

# ---------- deploy & interact ----------
anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS_ANVIL := --rpc-url $(RPC_URL_ANVIL) --private-key $(PRIVATE_KEY_ANVIL_0) --broadcast
NETWORK_ARGS_SEPOLIA := --rpc-url $(RPC_URL_SEPOLIA) --account $(ACCOUNT_DEV) --sender $(ADDRESS_DEV) --broadcast -vvvv
VERIFY := --verify --etherscan-api-key $(ETHERSCAN_API_KEY)
DEPLOY := forge script script/DeployDSC.s.sol:DeployDSC
DEPOSIT := forge script script/Interactions.s.sol:DepositCollateral
REDEEM := forge script script/Interactions.s.sol:RedeemCollateral
MINT := forge script script/Interactions.s.sol:MintDsc
BURN := forge script script/Interactions.s.sol:BurnDsc
DEPOSIT_AND_MINT := forge script script/Interactions.s.sol:DepositCollateralAndMintDsc
REDEEM_FOR_DSC := forge script script/Interactions.s.sol:RedeemCollateralForDsc
LIQUIDATE := forge script script/Interactions.s.sol:Liquidate

deploy :; $(DEPLOY) $(NETWORK_ARGS_ANVIL)
deploy-sepolia :; $(DEPLOY) $(NETWORK_ARGS_SEPOLIA) $(VERIFY)

mint-mock-weth :; forge script script/Interactions.s.sol:MintMockWethAnvil $(NETWORK_ARGS_ANVIL)

deposit :; $(DEPOSIT) $(NETWORK_ARGS_ANVIL)
deposit-sepolia :; $(DEPOSIT) $(NETWORK_ARGS_SEPOLIA)

redeem :; $(REDEEM) $(NETWORK_ARGS_ANVIL)
redeem-sepolia :; $(REDEEM) $(NETWORK_ARGS_SEPOLIA)

mint :; $(MINT) $(NETWORK_ARGS_ANVIL)
mint-sepolia :; $(MINT) $(NETWORK_ARGS_SEPOLIA)

burn :; $(BURN) $(NETWORK_ARGS_ANVIL)
burn-sepolia :; $(BURN) $(NETWORK_ARGS_SEPOLIA)

deposit-and-mint :; $(DEPOSIT_AND_MINT) $(NETWORK_ARGS_ANVIL)
deposit-and-mint-sepolia :; $(DEPOSIT_AND_MINT) $(NETWORK_ARGS_SEPOLIA)

redeem-for-dsc :; $(REDEEM_FOR_DSC) $(NETWORK_ARGS_ANVIL)
redeem-for-dsc-sepolia :; $(REDEEM_FOR_DSC) $(NETWORK_ARGS_SEPOLIA)

liquidate :; $(LIQUIDATE) $(NETWORK_ARGS_ANVIL)
liquidate-sepolia :; $(LIQUIDATE) $(NETWORK_ARGS_SEPOLIA)
