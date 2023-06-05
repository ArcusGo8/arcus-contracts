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
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IERC4907.sol";
import "hardhat/console.sol";

contract ArcusWarrior is
    Initializable,
    ERC721Upgradeable,
    IERC4907,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721URIStorageUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20;

    struct RenterInfo {
        address user;
        uint64 expiry;
    }

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");
    uint256 public constant EDITON = 1; // 1 = founder, 2 = limited, 3 = celebrity, 4 = regular
    uint256 public constant TRADEABLE = 2; // 1 = true, 0 = false
    uint256 public constant SUB_EDITION = 3;

    string public baseURI;
    CountersUpgradeable.Counter private _tokenIdCounter;

    mapping(uint256 => mapping(uint256 => uint256)) public tokenVars;
    mapping(uint256 => RenterInfo) internal renters;

    string public baseExtension;

    event WarriorMinted(
        uint256 indexed tokenId,
        address indexed minter,
        uint256 indexed edition,
        uint256 subEdition,
        uint256 rarity,
        bool tradeable,
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
        __ERC721_init("Arcus Warrior", "ARCWARRIOR");
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
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity,
        uint256 _amount
    ) public gameMasterOnly whenNotPaused {
        for (uint256 i = 0; i < _amount; i++)
            mint(_minter, _edition, _subEdition, _rarity);
    }

    function mint(
        address _minter,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity
    ) public gameMasterOnly whenNotPaused {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(_minter, tokenId);

        tokenVars[tokenId][EDITON] = _edition;
        tokenVars[tokenId][SUB_EDITION] = _subEdition;
        tokenVars[tokenId][TRADEABLE] = 1;

        emit WarriorMinted(
            tokenId,
            _minter,
            _edition,
            _subEdition,
            _rarity,
            true,
            uint64(block.timestamp)
        );
    }

    function mintFromChest(
        address _minter,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity,
        uint8 _tradeable
    ) public gameMasterOnly whenNotPaused returns (uint256) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(_minter, tokenId);

        tokenVars[tokenId][EDITON] = _edition;
        tokenVars[tokenId][SUB_EDITION] = _subEdition;
        tokenVars[tokenId][TRADEABLE] = _tradeable;

        emit WarriorMinted(
            tokenId,
            _minter,
            _edition,
            _subEdition,
            _rarity,
            (_tradeable == 1),
            uint64(block.timestamp)
        );
        return tokenId;
    }

    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) external gameMasterOnly {
        _setTokenURI(tokenId, _tokenURI);
    }

    function setBaseURI(string memory baseURI_) external gameMasterOnly {
        baseURI = baseURI_;
    }

    function setBaseExtension(
        string memory _baseExtension
    ) external gameMasterOnly {
        baseExtension = _baseExtension;
    }

    function getWarriorEdition(uint256 _tokenId) public view returns (uint256) {
        return tokenVars[_tokenId][EDITON];
    }

    function getWarriorSubEdition(
        uint256 tokenId
    ) public view returns (uint256) {
        return tokenVars[tokenId][SUB_EDITION];
    }

    function isTradeable(uint256 _tokenId) public view returns (bool) {
        return tokenVars[_tokenId][TRADEABLE] == 1;
    }

    function getUserWarriors(
        address user
    ) public view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](balanceOf(user));
        uint256 counter = 0;
        for (uint256 i = 1; i <= _tokenIdCounter.current(); i++) {
            if (ownerOf(i) == user) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
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

    function setUser(
        uint256 tokenId,
        address user,
        uint64 expires
    ) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "E6001");
        RenterInfo storage info = renters[tokenId];
        info.user = user;
        info.expiry = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    function userOf(uint256 tokenId) external view override returns (address) {
        if (uint256(renters[tokenId].expiry) >= block.timestamp) {
            return renters[tokenId].user;
        } else {
            return address(0);
        }
    }

    function userExpires(
        uint256 tokenId
    ) external view override returns (uint256) {
        return renters[tokenId].expiry;
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) {
        require(_isApprovedOrOwner(_from, _tokenId), "E5001");
        require(this.userOf(_tokenId) == address(0), "E6002");
        require(tokenVars[_tokenId][TRADEABLE] == 1, "E6003");
        super.safeTransferFrom(_from, _to, _tokenId);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) {
        safeTransferFrom(_from, _to, _tokenId);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function _burn(
        uint256 _tokenId
    ) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
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

        if (from != to && renters[tokenId].user != address(0)) {
            delete renters[tokenId];
            emit UpdateUser(tokenId, address(0), 0);
        }
    }

    function setNftVars(
        uint256 _tokenId,
        uint256 _key,
        uint256 _value
    ) public gameMasterOnly {
        tokenVars[_tokenId][_key] = _value;
    }

    function getNftVars(
        uint256 _tokenId,
        uint256 _key
    ) public view returns (uint256) {
        return tokenVars[_tokenId][_key];
    }
}
