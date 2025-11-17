import { HardhatUserConfig } from 'hardhat/config'
import networkHelpersPlugin from '@nomicfoundation/hardhat-network-helpers'
import viemPlugin from '@nomicfoundation/hardhat-viem'
import viemAssertionsPlugin from '@nomicfoundation/hardhat-viem-assertions'

const config: HardhatUserConfig = {
  plugins: [
    viemPlugin,
    viemAssertionsPlugin,
    networkHelpersPlugin
  ],
  solidity: {
    compilers: [
      {
        version: '0.8.28',
        settings: {
          evmVersion: 'cancun',
          optimizer: { enabled: true, runs: 1000000 },
          viaIR: true
        }
      }
    ]
  },
  paths: {
    sources: './src/',
  }
}

export default config
