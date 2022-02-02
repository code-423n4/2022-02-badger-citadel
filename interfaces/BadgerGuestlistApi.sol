// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// TODO: Maybe rename
interface BadgerGuestListAPI {
    function authorized(address guest, bytes32[] calldata merkleProof)
        external
        view
        returns (bool);

    function setGuests(address[] calldata _guests, bool[] calldata _invited)
        external;
}
