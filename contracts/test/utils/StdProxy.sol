// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract StdProxy {
    function deployProxy(
        bytes memory _creationCode,
        address _admin,
        bytes memory _data
    ) internal returns (address proxy_) {
        address logic;
        assembly {
            logic := create(0, add(_creationCode, 0x20), mload(_creationCode))
        }

        proxy_ = address(new TransparentUpgradeableProxy(logic, _admin, _data));
    }
}
