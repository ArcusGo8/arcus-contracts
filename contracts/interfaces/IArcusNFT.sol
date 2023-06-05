// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

interface IArcusNFT is IERC721Upgradeable {

    function mintN(
        address _minter,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _amount
    ) external;

    function mint(address _minter, uint256 _edition, uint256 _subEdition, uint256 _rarity) external;

    function mintFromChest(
        address _minter,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity,
        uint8 _tradeable
    ) external returns (uint256);

    function setNftVars(uint256 _tokenId, uint256 _key, uint256 _value) external;

    function getNftVars(uint256 _tokenId, uint256 _key) external view returns(uint256);

    function TRADEABLE() external returns(uint256);
}
