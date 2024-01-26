## ✨ Starport: Lending Kernel

Starport is a kernel for building lending protocols. A lending protocol can be implemented by inheriting and implementing the interfaces `Pricing`, `Status`, and `Settlement`. To learn more about how Starport works read the [Starport whitepaper](https://github.com/AstariaXYZ/starport-whitepaper/blob/master/starport-whitepaper.pdf).

## Deployments

### Canonical Cross-chain Deployment Addresses

<table>
<tr>
<th>Contract</th>
<th>Canonical Cross-chain Deployment Address</th>
</tr>
<tr>
<td>Starport</td>
<td><code>0x0000000000b1827b4959F2805E4b480D8799FCbB</code></td>
</tr>
<tr>
<td>Custodian</td>
<td><code>0x00000000c0c2Bae0eAA1b666fC2568CcaA9A9b3d</code></td>
</tr>
</table>

> Note: The canonical contracts for Starport, do not include modules. The modules included in this repository should be considered unsafe unless explicitly named in the audit report. 

### Deployments By EVM Chain

<table>
	<tr>
		<th>Network</th>
		<th>Starport</th>
		<th>Custodian</th>
	</tr>
	<tr>
		<td>
			Ethereum
		</td>
		<td>
			<a href="https://etherscan.io/address/0x0000000000b1827b4959F2805E4b480D8799FCbB#code"> 				0x0000000000b1827b4959F2805E4b480D8799FCbB
			</a> 
		</td>
		<td>
			<a href="https://etherscan.io/address/0x00000000c0c2Bae0eAA1b666fC2568CcaA9A9b3d#code"> 				0x00000000000001ad428e4906aE43D8F9852d0dD6
			</a>
		</td>
	</tr>
</table>

## Install

To install dependencies and compile contracts:

```bash
git clone --recurse-submodules https://github.com/AstariaXYZ/starport.git && cd starport
yarn install
forge build
```

## Usage
To run forge tests written in Solidity:

```
yarn test
```

## Audits
Astaria engaged Certora to audit and formally verify the security of Starport. From September 27th 2023 to January 24th 2024, a team of Certora auditors and formal verifiers conducted a security review of Starport. The audit did not uncover significant flaws that could result in the compromise of a smart contract, loss of funds, or unexpected behavior in the target system. The full report will me made available shortly.
## License

[BUSL-1.1](LICENSE) Copyright 2023 Astaria Labs, Inc.
