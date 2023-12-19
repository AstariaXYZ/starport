import { Address, hashTypedData, decodeAbiParameters, parseAbiParameters } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'


const types = {
  Origination: [
    {
      name: "account",
      type: "address"
    },
    {
      name: "accountNonce",
      type: "uint256"
    },
    {
      name: "singleUse",
      type: "bool"
    },
    {
      name: "salt",
      type: "bytes32"
    },
    {
      name: "deadline",
      type: "uint256"
    },
    {
      name: "caveats",
      type: "Caveat[]"
    }
  ],
  Caveat: [
    {
      name: "enforcer",
      type: "address"
    },
    {
      name: "data",
      type: "bytes"
    }
  ]
};


const domain = (verifyingContract: Address) => ({
  version: "0" ,
  verifyingContract: verifyingContract
});

type caveatType = [`0x${string}`, `0x${string}`];

const typeDataMessage = (account: Address, accountNonce: string, singleUse: number, salt: string, deadline: string, caveats: any) => ({
  account: account, accountNonce: accountNonce, singleUse: !!(singleUse), salt: salt, deadline: deadline, caveats: caveats
});

//verifying contract
//account
//singleUse
//salt
//deadline
//caveats

const args = process.argv.slice(2);

const main = async () => {
  const [signerKey, verifyingContract, account, accountNonce, singleUse, salt, deadline, caveatsRaw] = args;
  const signer = privateKeyToAccount(signerKey as `0x{string}`);//anvil account 1
  const caveats : any  = decodeAbiParameters(parseAbiParameters('(address,bytes)[]'), caveatsRaw as any );
  const message = typeDataMessage(account as Address, accountNonce, parseInt(singleUse), salt, deadline, caveats);
  console.log(message);
  const dataHash = await signer.signTypedData({
    domain: domain(verifyingContract as Address),
    types,
    primaryType: "Origination",
    message
  });

  console.log(dataHash);
}

main();