// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "forge-std/Vm.sol";

// Adapted from https://github.com/brockelmore/forge-std/blob/master/src/stdlib.sol

struct StdStorageInMemory {
    address _target;
    bytes4 _sig;
    bytes _keys;
    uint256 _depth;
}

library stdStorageInMemory {
    error NotFound(bytes4);
    error NotStorage(bytes4);
    error PackedSlot(bytes32);

    event SlotFound(address who, bytes4 fsig, bytes32 keysHash, uint256 slot);
    event WARNING_UninitedSlot(address who, uint256 slot);

    Vm constant stdstore_vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sigs(string memory sigStr) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(sigStr)));
    }

    /// @notice find an arbitrary storage slot given a function sig, input data, address of the contract and a value to check against
    // slot complexity:
    //  if flat, will be bytes32(uint256(uint));
    //  if map, will be keccak256(abi.encode(key, uint(slot)));
    //  if deep map, will be keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))));
    //  if map struct, will be bytes32(uint256(keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))))) + structFieldDepth);
    function find(StdStorageInMemory memory self) internal returns (uint256) {
        address who = self._target;
        bytes4 fsig = self._sig;
        uint256 field_depth = self._depth;
        bytes memory keys = self._keys;

        bytes memory cald = abi.encodePacked(fsig, keys);
        stdstore_vm.record();
        bytes32 fdat;
        {
            (, bytes memory rdat) = who.staticcall(cald);
            fdat = bytesToBytes32(rdat, 32 * field_depth);
        }

        bool found;
        uint256 slot;

        (bytes32[] memory reads, ) = stdstore_vm.accesses(address(who));
        if (reads.length == 1) {
            bytes32 curr = stdstore_vm.load(who, reads[0]);
            if (curr == bytes32(0)) {
                emit WARNING_UninitedSlot(who, uint256(reads[0]));
            }
            if (fdat != curr) {
                revert PackedSlot(reads[0]);
            }
            emit SlotFound(
                who,
                fsig,
                keccak256(abi.encodePacked(keys, field_depth)),
                uint256(reads[0])
            );
            found = true;
            slot = uint256(reads[0]);
        } else if (reads.length > 1) {
            for (uint256 i = 0; i < reads.length; i++) {
                bytes32 prev = stdstore_vm.load(who, reads[i]);
                if (prev == bytes32(0)) {
                    emit WARNING_UninitedSlot(who, uint256(reads[i]));
                }
                // store
                stdstore_vm.store(who, reads[i], bytes32(hex"1337"));
                {
                    (, bytes memory rdat) = who.staticcall(cald);
                    fdat = bytesToBytes32(rdat, 32 * field_depth);
                }

                if (fdat == bytes32(hex"1337")) {
                    // we found which of the slots is the actual one
                    emit SlotFound(
                        who,
                        fsig,
                        keccak256(abi.encodePacked(keys, field_depth)),
                        uint256(reads[i])
                    );
                    stdstore_vm.store(who, reads[i], prev);
                    found = true;
                    slot = uint256(reads[i]);
                    break;
                }
                stdstore_vm.store(who, reads[i], prev);
            }
        } else {
            revert NotStorage(fsig);
        }

        if (!found) revert NotFound(fsig);

        delete self._target;
        delete self._sig;
        delete self._keys;
        delete self._depth;

        return slot;
    }

    function target(StdStorageInMemory memory self, address _target)
        internal
        returns (StdStorageInMemory memory)
    {
        self._target = _target;
        return self;
    }

    function sig(StdStorageInMemory memory self, bytes4 _sig)
        internal
        returns (StdStorageInMemory memory)
    {
        self._sig = _sig;
        return self;
    }

    function sig(StdStorageInMemory memory self, string memory _sig)
        internal
        returns (StdStorageInMemory memory)
    {
        self._sig = sigs(_sig);
        return self;
    }

    function with_keys(StdStorageInMemory memory self, bytes memory keys)
        internal
        returns (StdStorageInMemory memory)
    {
        self._keys = keys;
        return self;
    }

    function depth(StdStorageInMemory memory self, uint256 _depth)
        internal
        returns (StdStorageInMemory memory)
    {
        self._depth = _depth;
        return self;
    }

    function checked_write(StdStorageInMemory memory self, address who)
        internal
    {
        checked_write(self, bytes32(uint256(uint160(who))));
    }

    function checked_write(StdStorageInMemory memory self, uint256 amt)
        internal
    {
        checked_write(self, bytes32(amt));
    }

    function checked_write(StdStorageInMemory memory self, bytes32 set)
        internal
    {
        address who = self._target;
        bytes4 fsig = self._sig;
        uint256 field_depth = self._depth;
        bytes memory keys = self._keys;

        bytes memory cald = abi.encodePacked(fsig, keys);
        bytes32 slot = bytes32(find(self));

        bytes32 fdat;
        {
            (, bytes memory rdat) = who.staticcall(cald);
            fdat = bytesToBytes32(rdat, 32 * field_depth);
        }
        bytes32 curr = stdstore_vm.load(who, slot);

        if (fdat != curr) {
            revert PackedSlot(slot);
        }
        stdstore_vm.store(who, slot, set);
        delete self._target;
        delete self._sig;
        delete self._keys;
        delete self._depth;
    }

    function bytesToBytes32(bytes memory b, uint256 offset)
        public
        pure
        returns (bytes32)
    {
        bytes32 out;

        for (uint256 i = 0; i < 32; i++) {
            out |= bytes32(b[offset + i] & 0xFF) >> (i * 8);
        }
        return out;
    }
}
