// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract WhitelistManager is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20;

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");
    uint64 public constant MAX_FEE = 10_000;

    modifier ownerOnly() {
        _isOwner();
        _;
    }

    modifier gameMasterOnly() {
        _isGameMaster();
        _;
    }

    // internal/private functions

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
        whenNotPaused
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // external/public functions

    function initialize() public initializer {
        __ERC1155_init("");
        __AccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_MASTER, msg.sender);
    }

    function setURI(string memory newuri) public gameMasterOnly {
        _setURI(newuri);
    }

    function pause() public ownerOnly {
        _pause();
    }

    function unpause() public ownerOnly {
        _unpause();
    }

    // gamemaster/owner can issue whitelist token to partners
    function mintWhitelistToken(
        uint256 _tokenId,
        uint256 _quantity,
        address _to
    ) public gameMasterOnly {
        _mint(_to, _tokenId, _quantity, "");
    }

    function bulkSafeTransferFrom(
        address _from,
        uint256 _tokenId,
        address[] memory _receivers,
        uint256[] memory _amounts
    ) public {
        require(_receivers.length == _amounts.length, "E3501");
        require(_receivers.length <= 500, "E3502");

        uint256 totalAmount;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount.add(_amounts[i]);
        }
        require(balanceOf(_from, _tokenId) >= totalAmount, "E3001");
        for (uint256 i = 0; i < _receivers.length; i++) {
            safeTransferFrom(_from, _receivers[i], _tokenId, _amounts[i], "");
        }
    }

    function transfer(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        safeTransferFrom(_from, _to, _tokenId, _amount, "");
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
