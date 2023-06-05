// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract ArcusChest is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721URIStorageUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20Upgradeable for IERC20;

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");

    string public baseURI;
    CountersUpgradeable.Counter private _tokenIdCounter;

    mapping(uint256 => mapping(uint256 => uint256)) public tokenVars;
    mapping(uint256 => uint256) public arcusChestIds;
    
    EnumerableSet.UintSet chestIds;
    
    string public baseExtension;

    event ArcusChestMinted(
        uint256 indexed tokenId,
        uint256 indexed chestId,
        address indexed minter,
        uint64 timestamp
    );

    modifier ownerOnly() {
        _isOwner();
        _;
    }
    modifier gameMasterOnly() {
        _isGameMaster();
        _;
    }

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function initialize(string memory baseURI_) public initializer {
        __ERC721_init("Arcus Chest", "ARCCHEST");
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_MASTER, msg.sender);
        baseURI = baseURI_;
    }

    function pause() public ownerOnly {
        _pause();
    }

    function unpause() public ownerOnly {
        _unpause();
    }

    function mintN(
        address _minter,
        uint256 _chestId,
        uint256 _amount
    ) public gameMasterOnly whenNotPaused returns (uint256[] memory tokenIds) {
        for (uint256 i = 0; i < _amount; i++)
            tokenIds[i] = mint(_minter, _chestId);
    }

    function mint(address _minter, uint256 _chestId)
        public
        gameMasterOnly
        whenNotPaused
        returns (uint256 tokenId)
    {
        _tokenIdCounter.increment();
        tokenId = _tokenIdCounter.current();
        _safeMint(_minter, tokenId);

        arcusChestIds[tokenId] = _chestId;
        chestIds.add(tokenId);

        emit ArcusChestMinted(
            tokenId,
            _chestId,
            _minter,
            uint64(block.timestamp)
        );
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        external
        gameMasterOnly
    {
        _setTokenURI(tokenId, _tokenURI);
    }

    function setBaseURI(string memory baseURI_) external gameMasterOnly {
        baseURI = baseURI_;
    }

    function setBaseExtension(string memory _baseExtension)
        external
        gameMasterOnly
    {
        baseExtension = _baseExtension;
    }

    function getUserChests(address user)
        public
        view
        returns (uint256[] memory)
    {
        EnumerableSet.UintSet storage set = chestIds;
        uint256[] memory result = new uint256[](balanceOf(user));
        uint256 counter = 0;
        for (uint256 i = 0; i < set.length(); i++) {
            if (ownerOf(set.at(i)) == user) {
                result[counter] = set.at(i);
                counter++;
            }
        }
        return result;
    }

    function getChestId(uint256 _tokenId) public view returns (uint256) {
        return arcusChestIds[_tokenId];
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721Upgradeable,
            ERC721URIStorageUpgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    baseURI,
                    Strings.toString(_tokenId),
                    baseExtension
                )
            );
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) {
        require(_isApprovedOrOwner(_from, _tokenId), "E5001");
        super.safeTransferFrom(_from, _to, _tokenId);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) {
        safeTransferFrom(_from, _to, _tokenId);
    }

    function burn(
        uint256 _tokenId
    ) public override {
        chestIds.remove(_tokenId);
        _burn(_tokenId);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function _burn(uint256 _tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(_tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}
