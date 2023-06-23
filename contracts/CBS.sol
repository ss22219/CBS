// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC1400.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title CBS
 * @dev This contract extends the ERC1400 contract with additional functionality
 * to charge transfer fees that are sent to specific addresses.
 */
contract CBS is ERC1400 {
    using SafeMath for uint256;

    address public prosynergy; // Address to receive the 1% issue fee and 0.125% transaction fee
    address public citd; // Address to receive the 0.25% transaction fee
    mapping(address => bool) public whitelist;

    /**
     * @dev Sets the values for {_owner}, {_to}, {_feeAddr1} and {_citd}.
     *
     * The defaut value of {name} is 'CITD Bond STO', and {symbol} is 'CBS'.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        address _owner,
        address _to,
        address _prosynergy,
        address _citd
    ) ERC1400("CITD Bond STO", "CBS", 1) {
        if (_owner != msg.sender) transferOwnership(_owner);
        prosynergy = _prosynergy;
        citd = _citd;
        whitelist[_to] = true;
        _issueByPartition(
            _defaultPartition,
            msg.sender,
            _to,
            100_000_000 * 1e18,
            ""
        );
    }

    /**
     * @dev Updates the fee addresses.
     * Can only be called by the contract owner.
     */
    function upgradeFeeAddr(
        address _prosynergy,
        address _citd
    ) public onlyOwner {
        prosynergy = _prosynergy;
        citd = _citd;
    }

    /**
     * @notice Sets the whitelist status for an address
     * @param _addr The address to set the whitelist status for
     * @param _state Whether the address should be whitelisted or not
     * @dev Can only be called by the contract owner
     */
    function setWhitelist(address _addr, bool _state) public onlyOwner {
        whitelist[_addr] = _state;
    }

    /**
     * @dev Executes a transfer by partition and charges transfer fees.
     */
    function _transferByPartition(
        bytes32 fromPartition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes memory data,
        bytes memory operatorData
    ) internal override returns (bytes32) {
        if (_checkWhiteList(from, to))
            return
                super._transferByPartition(
                    fromPartition,
                    operator,
                    from,
                    to,
                    value,
                    data,
                    operatorData
                );

        require(_balanceOfByPartition[from][fromPartition] >= value, "52"); // 0x52 insufficient balance

        bytes32 toPartition = fromPartition;
        if (operatorData.length != 0 && data.length >= 64) {
            toPartition = _getDestinationPartition(fromPartition, data);
        }

        if (toPartition != fromPartition) {
            emit ChangedPartition(fromPartition, toPartition, value);
        }

        uint256 citdFeeAmount = value.mul(250).div(100000); // 0.25%
        uint256 prosynergyFeeAmount = value.mul(125).div(100000); // 0.125%

        _removeTokenFromPartition(from, fromPartition, value);
        value = value.sub(prosynergyFeeAmount).sub(citdFeeAmount);

        _transferWithData(from, to, value);
        _addTokenToPartition(to, toPartition, value);
        emit TransferByPartition(
            fromPartition,
            operator,
            from,
            to,
            value,
            data,
            operatorData
        );

        //transfer prosynergy fee
        if (prosynergyFeeAmount > 0 && prosynergy != address(0)) {
            _transferWithData(from, prosynergy, prosynergyFeeAmount);
            _addTokenToPartition(prosynergy, toPartition, prosynergyFeeAmount);
            emit TransferByPartition(
                fromPartition,
                operator,
                from,
                prosynergy,
                prosynergyFeeAmount,
                data,
                operatorData
            );
        }

        //transfer citd fee
        if (citdFeeAmount > 0 && citd != address(0)) {
            _transferWithData(from, citd, citdFeeAmount);
            _addTokenToPartition(citd, toPartition, citdFeeAmount);
            emit TransferByPartition(
                fromPartition,
                operator,
                from,
                citd,
                citdFeeAmount,
                data,
                operatorData
            );
        }

        return toPartition;
    }

    /**
     * @dev Returns true if the `from` or `to` address is in the whitelist.
     */
    function _checkWhiteList(
        address from,
        address to
    ) internal view returns (bool) {
        if (from == to) return true;
        if (from == prosynergy || from == citd || from == owner()) return true;
        if (to == prosynergy || to == citd || to == owner()) return true;
        return whitelist[to] || whitelist[from];
    }

    function _issueByPartition(
        bytes32 toPartition,
        address operator,
        address to,
        uint256 value,
        bytes memory data
    ) internal override {
        uint256 issueFee = value.mul(1000).div(100000);

        if (prosynergy != address(0)) {
            value = value.sub(issueFee);
            _issue(operator, prosynergy, issueFee, data);
            _addTokenToPartition(prosynergy, toPartition, issueFee);
            emit IssuedByPartition(toPartition, operator, prosynergy, issueFee, data, "");
        }
        
        _issue(operator, to, value, data);
        _addTokenToPartition(to, toPartition, value);
        emit IssuedByPartition(toPartition, operator, to, value, data, "");
    }
}
