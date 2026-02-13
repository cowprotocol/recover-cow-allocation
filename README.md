# Cow allocation token recovery

The contracts in this repo are used to withdraw funds from [COW team allocations](https://github.com/cowprotocol/team-cow-allocation/) out of compromised wallets that have a valid claim.

The first thing to do when a wallet with a claim is compromised is **disabling the COW allocation module** from the team multisig as soon as possible.
This makes it impossible for anyone to use their allocation, effectively freezing the funds (but the vesting still continues).

However, even if frozen, the allocation cannot be transferred.
At this point, these contracts come into play: it's possible to recover the funds from an allocation for a compromised address as long as both the team multisig and the claim owners cooperate.
The process is robust, meaning that the adversary won't be able to steal the funds even with knowledge of what is transpiring.
As long as the allocation module is disabled, the process isn't time-sensitive.

The process is the following:
1. The compromised user shares a known-good address for the allocation (receiver) and the compromised wallet (user).
2. The contracts on this repo are [deployed](#deploy) with the parameters from the previous point.
3. The compromised user needs to [sign a delegation authentication](#sign-a-delegation-authentication) to be used in a later step.
4. The team multisig owners need to [sign the following three transactions](#create-the-multisig-transaction) in the same batch:
   1. Enable the COW allocation module.
   2. Stop the claim of the compromised address. This claims all remaining COW tokens for the user.
   3. Call the trigger function on the deployed `DelegateTrigger`. This transfers 
   It's critical that all three are executed in the same batch: we need to make sure that the adversary cannot just re-enable the module and steal the allocation before the trigger is executed.
5. Once signed, the transaction needs to be [executed while including the delegation authentication](#execute-the-multisig-transaction-with-the-delegate) from step 3.

After all these steps are completed, the module will be enabled again, the compromised wallet won't have any remaining tokens to claim, and the COW tokens accumulated so far in the claim will have been sent to the known-good address.

## Usage

### Deploy

Test run:

```shell
PK=<your_private_key>
RPC_URL=<your_rpc_url>
USER=<the possibly untrusted user address; the address that has a COW allocation>
RECEIVER=<a trusted receiver address; it will receive the funds from USER>
forge script --rpc-url "$RPC_URL" --private-key "$PK" 'script/DeployAll.s.sol:DeployAll' "$RECEIVER" "$OWNER"
```

To actually deploy and verify the contract on Etherscan:

```shell
ETHERSCAN_API_KEY=<your_etherscan_api_key>
forge script --rpc-url "$RPC_URL" --private-key "$PK" --etherscan-api-key "$ETHERSCAN_API_KEY" 'script/DeployAll.s.sol:DeployAll' "$RECEIVER" "$OWNER" --broadcast --verify
```

### Contract verification

If the contract wasn't verified on deployment, it can be verified as follows.

```shell
ETHERSCAN_API_KEY=<your_etherscan_api_key>
RPC_URL=<your_rpc_url>
TRIGGER=<address of the DelegateTrigger contract>
forge verify-contract --rpc-url "$RPC_URL" --etherscan-api-key "$ETHERSCAN_API_KEY" --watch "$TRIGGER" 'src/DelegateTrigger.sol:DelegateTrigger'
RECOVERING_DELEGATE=$(cast call --rpc-url "$RPC_URL"  "$TRIGGER"  'DELEGATE()(address)')
forge verify-contract --rpc-url "$RPC_URL" --etherscan-api-key "$ETHERSCAN_API_KEY" --watch "$RECOVERING_DELEGATE" 'src/RecoveringDelegate.sol:RecoveringDelegate'
```

### Sign a delegation authentication

The compromiser user needs to use the (compromised) private key to create an [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) delegation authentication.
The easiest way to do this is by using `cast`:

```shell
PK=<the compromised private key of the user>
RPC_URL=<your_rpc_url>
RECOVERING_DELEGATE=<the address of the deployed RecoveringDelegate contract with the expected parameters>
cast wallet sign-auth --rpc-url "$RPC_URL" --private-key "$PK" "$RECOVERING_DELEGATE"
```

The result should be a hexadecimal string of 124 characters, starting with `0x`.
This string should be shared at a later step.

### Create the multisig transaction

As an owner of the team multisig, go to the [transaction builder page](https://app.safe.global/apps/open?safe=eth%3A0xca07EaA4253638D286caD71CBcEec11803F2709A&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder).

You need the following information:
- the compromised address of the user (`USER` in the description that follows),
- the deployed `DelegateTrigger` contract (`DELEGATE_TRIGGER`),

Add the following transactions:

1. Enabling the allocation module.
   Address or ENS name: `0xca07EaA4253638D286caD71CBcEec11803F2709A` (the team multisig; it calls itself).
   Click on "use implementation ABI" when prompted.
   Select contract method `enableModule`.
   Input value `module` is `0x582A254713b65c140840ade25A692fBe2610682d` (the allocation module; this address may be outdated, you can see the latest [here](https://github.com/cowprotocol/team-cow-allocation/blob/main/networks.json)).
   Add the transaction to the batch.
2. Disable the allocation for the user.
   Address or ENS name: `0x582A254713b65c140840ade25A692fBe2610682d` (same as before).
   Select contract method `stopClaim`.
   Input value `beneficiary` is `USER` from the information you collected from the start.
   Add the transaction to the batch.
3. Trigger the withdrawal.
   Address or ENS name: `DELEGATE_TRIGGER` (from the information you collected from the start).
   You may need to import the ABI: you can find it on Etherscan under the code page of `DELEGATE_TRIGGER`.
   Select contract method `stopClaim`.
   Input value `token` is `0xDEf1CA1fb7FBcDC777520aa7f396b4E015F497aB` (the COW token address).
   Add the transaction to the batch.

Note that the batch is **expected to fail simulation**.
This is because the delegate authentication hasn't been included and without that we want the transaction to be reverting, since it's what allows the funds to be withdrawn.
Unfortunately, there's no way to simulate the addition of a delegate on Tenderly at the time of writing.

### Execute the multisig transaction with the delegate

Once enough signatures have been collected, anyone should be able to execute the multisig transaction.

The easiest way to get the transaction data is by trying to execute the transaction on the Safe interface. Do not actually execute the transaction!
Then, it should be possible to get the `DATA` used by the transaction out of the wallet interface.
If this doesn't work, using the [wallet impersonator](https://impersonator.xyz/) is also an option since it lets you see the data of all submitted transactions.
`DATA` is a very long hex string.

You'll also need the delegation authentication from a [previous step](#sign-a-delegation-authentication).

Once you have this information, you can execute the multisig transaction with a Type-4 transaction that sets the EIP-7702 delegate.
Concretely, this can be done with Foundry as follows.

```shell
PK=<any private key with some funds that can execute the transaction>
RPC_URL=<your_rpc_url>
AUTH=<the signed delegation authentication from>
TEAM_MULTISIG='0xca07EaA4253638D286caD71CBcEec11803F2709A'
DATA=<the DATA information collected above>
cast send --rpc-url "$RPC_URL" --auth "$AUTH" --private-key "$PK" "$TEAM_MULTISIG" "$DATA"
```

### Build

```shell
forge build
```

### Test

Only local tests:

```shell
forge test --no-match-contract 'E2e*'
```

All tests:

```shell
export MAINNET_RPC_URL=<an URL pointing to an archive node for Ethereum mainnet>
forge test
```

### Format

```shell
forge fmt
```
