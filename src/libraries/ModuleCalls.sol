// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Shared call plumbing for the game's fixed-width module ABIs.
/// @dev Callers still use abi.encodeCall and abi.decode for type checking. Copy only the expected
/// static return words (as Solidity does), reject short replies, and propagate failures unchanged.
/// All functions are internal: there are no linked libraries or delegate calls.
library ModuleCalls {
    function read(address target, bytes memory input, uint256 size)
        internal
        view
        returns (bytes memory output)
    {
        assembly ("memory-safe") {
            // All production callers pass a fixed multiple of 32, at most 288 bytes. The call
            // overwrites every expected word or reverts, so the buffer needs no zero-fill.
            output := mload(0x40)
            mstore(output, size)
            mstore(0x40, and(add(add(output, size), 63), not(31)))
            if iszero(staticcall(gas(), target, add(input, 32), mload(input), add(output, 32), size)) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
            if lt(returndatasize(), size) { revert(0, 0) }
        }
    }

    function invoke(address target, bytes memory input, uint256 size) internal returns (bytes memory output) {
        assembly ("memory-safe") {
            // All production callers pass a fixed multiple of 32, at most 288 bytes. The call
            // overwrites every expected word or reverts, so the buffer needs no zero-fill.
            output := mload(0x40)
            mstore(output, size)
            mstore(0x40, and(add(add(output, size), 63), not(31)))
            // Solidity checks code existence for calls with no return values. For fixed-width
            // replies the length check below already rejects an address without code.
            if iszero(size) {
                if iszero(extcodesize(target)) { revert(0, 0) }
            }
            if iszero(call(gas(), target, 0, add(input, 32), mload(input), add(output, 32), size)) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
            if lt(returndatasize(), size) { revert(0, 0) }
        }
    }
}
