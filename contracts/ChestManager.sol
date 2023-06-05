// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IArcusNFT.sol";
import "./ArcusChest.sol";
import "./SeedManager.sol";
import "./lib/Random.sol";
import "hardhat/console.sol";

contract ChestManager is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20;

    enum TokenType {
        ERC1155,
        ERC721
    }

    struct ChestItem {
        address nftAddress;
        uint64 chance;
        uint256 quantity;
        uint256 edition;
        uint256 subEdition;
        uint256 rarity;
        uint8 tradeable;
    }

    struct NFTChest {
        uint256 price;
        address paymentToken;
        uint256 maxItems;
        uint256 totalWeight;
        bool active;
    }

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");
    uint256 internal constant PACK_RANDOM_SEED =
        uint256(keccak256("PACK_RANDOM_SEED"));

    CountersUpgradeable.Counter private _chestIdCounter;
    EnumerableSet.AddressSet private allowedPaymentTokens;
    EnumerableSet.AddressSet private allowedNFTs;
    EnumerableSet.UintSet private activeChestIds;

    address public treasury;
    ArcusChest public arcusChest;
    SeedManager public seedManager;

    mapping(address => TokenType) tokenTypes;
    mapping(uint256 => NFTChest) public nftChests;
    mapping(uint256 => uint256) public nftChestsType; // 1 = pack, 2 = gacha
    mapping(uint256 => ChestItem[]) nftChestItems;

    event NewNFTChest(
        uint256 indexed chestId,
        address indexed paymentToken,
        uint256 indexed chestType,
        uint256 price,
        uint256 maxItems,
        bool active,
        uint64 timestamp
    );

    event UpdatedNFTChest(
        uint256 indexed chestId,
        address indexed paymentToken,
        uint256 indexed chestType,
        uint256 price,
        uint256 maxItems,
        bool active,
        uint64 timestamp
    );

    event NewNFTChestItem(
        uint256 indexed chestId,
        uint256 indexed indexId,
        address indexed nftAddress,
        uint256 chance,
        uint256 quantity,
        uint256 edition,
        uint256 subEdition,
        uint256 rarity,
        uint8 tradeable,
        uint64 timestamp
    );

    event UpdatedNFTChestItem(
        uint256 indexed chestId,
        uint256 indexed indexId,
        address indexed nftAddress,
        uint256 chance,
        uint256 quantity,
        uint256 edition,
        uint256 subEdition,
        uint256 rarity,
        uint8 tradeable,
        uint64 timestamp
    );

    event NFTChestOpened(
        uint256 indexed chestId,
        address indexed user,
        uint256 tokenId,
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
    modifier nftCollectionAllowed(address _nftAddress) {
        _nftCollectionAllowed(_nftAddress);
        _;
    }
    modifier paymentTokenAllowed(address _paymentToken) {
        _paymentTokenAllowed(_paymentToken);
        _;
    }

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function _nftCollectionAllowed(address _nftAddress) private view {
        require(allowedNFTs.contains(_nftAddress), "E4002");
    }

    function _paymentTokenAllowed(address _paymentToken) private view {
        require(allowedPaymentTokens.contains(_paymentToken), "E2001");
    }

    function _getRandomItems(
        uint256 _seed,
        uint256 _chestId
    ) private view returns (uint256[] memory) {
        ChestItem[] memory chestItems = nftChestItems[_chestId];
        uint256[] memory selectedItems = new uint256[](
            nftChests[_chestId].maxItems
        );
        uint256 roll;
        uint256 cumulativeWeight;
        for (uint256 i = 0; i < nftChests[_chestId].maxItems; i++) {
            roll =
                Random.combineSeeds(_seed, i) %
                nftChests[_chestId].totalWeight;
            cumulativeWeight = 0;
            for (uint256 j = 0; j < chestItems.length; j++) {
                cumulativeWeight += chestItems[j].chance;
                if (roll < cumulativeWeight) {
                    selectedItems[i] = j;
                    break;
                }
            }
        }
        return selectedItems;
    }

    function _getChestItems(
        uint256 _chestId
    ) private view returns (uint256[] memory) {
        ChestItem[] memory chestItems = nftChestItems[_chestId];
        uint256 selectedItemCount;
        uint256[] memory itemIds = new uint256[](chestItems.length);
        for (uint256 i = 0; i < chestItems.length; i++) {
            itemIds[selectedItemCount] = i;
            selectedItemCount++;
        }
        return itemIds;
    }

    function _mintSelectedItems(
        uint256[] memory _selectedItems,
        uint256 _chestId,
        address _minter
    ) private {
        require(_selectedItems.length > 0, "E7007");
        for (uint256 i = 0; i < _selectedItems.length; i++) {
            IArcusNFT(nftChestItems[_chestId][_selectedItems[i]].nftAddress)
                .mintFromChest(
                    _minter,
                    nftChestItems[_chestId][_selectedItems[i]].edition,
                    nftChestItems[_chestId][_selectedItems[i]].subEdition,
                    nftChestItems[_chestId][_selectedItems[i]].rarity,
                    nftChestItems[_chestId][_selectedItems[i]].tradeable
                );
        }
    }

    function initialize(
        address _treasury,
        ArcusChest _arcusChest,
        SeedManager _seedManager
    ) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAME_MASTER, msg.sender);

        treasury = _treasury;
        arcusChest = _arcusChest;
        seedManager = _seedManager;
    }

    function setTreasury(address _treasury) public ownerOnly {
        require(_treasury != address(0), "E5006");
        treasury = _treasury;
    }

    function addAllowedPaymentToken(
        address _paymentToken
    ) external gameMasterOnly {
        require(!allowedPaymentTokens.contains(_paymentToken), "E2002");
        allowedPaymentTokens.add(_paymentToken);
    }

    function removeAllowedPaymentToken(
        address _paymentToken
    ) external gameMasterOnly paymentTokenAllowed(_paymentToken) {
        allowedPaymentTokens.remove(_paymentToken);
    }

    function getAllowedPaymentTokens()
        external
        view
        returns (address[] memory)
    {
        EnumerableSet.AddressSet storage set = allowedPaymentTokens;
        address[] memory tokens = new address[](set.length());

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = set.at(i);
        }
        return tokens;
    }

    function addAllowedNft(address _nftAddress) external gameMasterOnly {
        require(!allowedNFTs.contains(_nftAddress), "E4001");
        allowedNFTs.add(_nftAddress);
        tokenTypes[_nftAddress] = getTokenType(_nftAddress);
    }

    function removeAllowedNft(
        address _nftAddress
    ) external gameMasterOnly nftCollectionAllowed(_nftAddress) {
        allowedNFTs.remove(_nftAddress);
        delete tokenTypes[_nftAddress];
    }

    function getAllowedNfts() external view returns (address[] memory) {
        EnumerableSet.AddressSet storage set = allowedNFTs;
        address[] memory tokens = new address[](set.length());

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = set.at(i);
        }
        return tokens;
    }

    function getTokenType(
        address _nftAddress
    ) internal view returns (TokenType tokenType) {
        if (
            IERC165Upgradeable(_nftAddress).supportsInterface(
                type(IERC1155Upgradeable).interfaceId
            )
        ) {
            tokenType = TokenType.ERC1155;
        } else if (
            IERC165Upgradeable(_nftAddress).supportsInterface(
                type(IERC721Upgradeable).interfaceId
            )
        ) {
            tokenType = TokenType.ERC721;
        } else {
            revert("token must be ERC1155 or ERC721.");
        }
    }

    function getCurrentChestId() public view returns (uint256) {
        return _chestIdCounter.current();
    }

    function getNftChestItems(
        uint256 _chestId
    ) public view returns (ChestItem[] memory) {
        return nftChestItems[_chestId];
    }

    function getNftChestIds() public view returns (uint256[] memory) {
        uint256[] memory chestIds = new uint256[](getCurrentChestId());
        for (uint256 i = 0; i < getCurrentChestId(); i++) {
            chestIds[i] = i.add(1);
        }
        return chestIds;
    }

    function getActiveChestIds() public view returns (uint256[] memory) {
        EnumerableSet.UintSet storage set = activeChestIds;
        uint256[] memory chestIds = new uint256[](set.length());

        for (uint256 i = 0; i < chestIds.length; i++) {
            chestIds[i] = set.at(i);
        }
        return chestIds;
    }

    function newNftChest(
        address _paymentToken,
        uint256 _price,
        uint256 _chestType,
        uint256 _maxItems,
        bool _active
    ) public gameMasterOnly paymentTokenAllowed(_paymentToken) {
        require(_chestType > 0, "E7001");
        _chestIdCounter.increment();
        uint256 chestId = _chestIdCounter.current();
        NFTChest storage nftChest = nftChests[chestId];
        nftChest.price = _price;
        nftChest.paymentToken = _paymentToken;
        nftChest.maxItems = _maxItems;
        nftChest.active = _active;
        nftChestsType[chestId] = _chestType;

        if (_active) {
            activeChestIds.add(chestId);
        }

        emit NewNFTChest(
            chestId,
            _paymentToken,
            _chestType,
            _price,
            _maxItems,
            _active,
            uint64(block.timestamp)
        );
    }

    function addChestItem(
        uint256 _chestId,
        ChestItem memory _chestItem
    ) public gameMasterOnly {
        require(allowedNFTs.contains(_chestItem.nftAddress), "E4003");
        require(_chestItem.quantity > 0, "E7003");
        nftChestItems[_chestId].push(_chestItem);
        nftChests[_chestId].totalWeight = nftChests[_chestId].totalWeight.add(
            _chestItem.chance
        );

        emit NewNFTChestItem(
            _chestId,
            nftChestItems[_chestId].length - 1,
            _chestItem.nftAddress,
            _chestItem.chance,
            _chestItem.quantity,
            _chestItem.edition,
            _chestItem.subEdition,
            _chestItem.rarity,
            _chestItem.tradeable,
            uint64(block.timestamp)
        );
    }

    function mintNftChest(uint256 _chestId) public nonReentrant {
        require(nftChests[_chestId].active, "E7004");
        require(
            IERC20(nftChests[_chestId].paymentToken).balanceOf(msg.sender) >=
                nftChests[_chestId].price,
            "E3002"
        );
        arcusChest.mint(msg.sender, _chestId);
        if (nftChests[_chestId].price > 0) {
            IERC20(nftChests[_chestId].paymentToken).transferFrom(
                msg.sender,
                treasury,
                nftChests[_chestId].price
            );
        }
    }

    function openNftChest(uint256 _tokenId) public nonReentrant {
        require(arcusChest.ownerOf(_tokenId) == msg.sender, "E7006");
        uint256 chestId = arcusChest.getChestId(_tokenId);
        require(chestId > 0, "E7005");
        uint256[] memory selectedItems;
        if (nftChestsType[chestId] == 1) {
            selectedItems = _getChestItems(chestId);
        } else {
            selectedItems = _getRandomItems(
                seedManager.popSingleSeed(
                    address(this),
                    uint(keccak256(abi.encodePacked(PACK_RANDOM_SEED, msg.sender))),
                    true,
                    true
                ),
                chestId
            );
        }
        _mintSelectedItems(selectedItems, chestId, msg.sender);
        arcusChest.burn(_tokenId);
        emit NFTChestOpened(
            chestId,
            msg.sender,
            _tokenId,
            uint64(block.timestamp)
        );
    }

    function isSeedRequired(uint256 _tokenId) public view returns(bool) {
        return nftChestsType[arcusChest.getChestId(_tokenId)] != 1;
    }

    function generateSeed() public nonReentrant {
        seedManager.requestSingleSeed(
            address(this),
            uint(keccak256(abi.encodePacked(PACK_RANDOM_SEED, msg.sender)))
        );
    }

    function hasSeedRequested(address _user) public view returns (bool) {
        return seedManager.hasSingleSeedRequest(
                address(this),
                uint(keccak256(abi.encodePacked(PACK_RANDOM_SEED, _user)))
            );
    }

    function updateNftChest(
        uint256 _chestId,
        address _paymentToken,
        uint256 _price,
        uint256 _chestType,
        uint256 _maxItems,
        bool _active
    ) public gameMasterOnly paymentTokenAllowed(_paymentToken) {
        require(_chestId > 0, "E7005");
        require(_chestType > 0, "E7001");
        if (nftChests[_chestId].paymentToken != _paymentToken) {
            nftChests[_chestId].paymentToken = _paymentToken;
        }
        if (nftChests[_chestId].price != _price) {
            nftChests[_chestId].price = _price;
        }
        if (nftChestsType[_chestId] != _chestType) {
            nftChestsType[_chestId] = _chestType;
        }
        if (nftChests[_chestId].maxItems != _maxItems) {
            nftChests[_chestId].maxItems = _maxItems;
        }
        if (nftChests[_chestId].active != _active) {
            nftChests[_chestId].active = _active;
            if (!_active) {
                activeChestIds.remove(_chestId);
            } else {
                activeChestIds.add(_chestId);
            }
        }

        emit UpdatedNFTChest(
            _chestId,
            _paymentToken,
            _chestType,
            _price,
            _maxItems,
            _active,
            uint64(block.timestamp)
        );
    }

    function updateChestItem(
        uint256 _chestId,
        uint256 _itemIndex,
        ChestItem memory _chestItem
    ) public gameMasterOnly {
        require(_chestId > 0, "E7005");
        require(_itemIndex < nftChestItems[_chestId].length, "E7008");
        if (
            nftChestItems[_chestId][_itemIndex].nftAddress !=
            _chestItem.nftAddress
        ) {
            require(allowedNFTs.contains(_chestItem.nftAddress), "E4003");
            nftChestItems[_chestId][_itemIndex].nftAddress = _chestItem
                .nftAddress;
        }
        if (nftChestItems[_chestId][_itemIndex].chance != _chestItem.chance) {
            uint256 totalWeight = nftChests[_chestId].totalWeight;
            totalWeight = totalWeight.sub(
                nftChestItems[_chestId][_itemIndex].chance
            );
            totalWeight = totalWeight.add(_chestItem.chance);
            nftChestItems[_chestId][_itemIndex].chance = _chestItem.chance;
            nftChests[_chestId].totalWeight = totalWeight;
        }
        if (
            nftChestItems[_chestId][_itemIndex].quantity != _chestItem.quantity
        ) {
            nftChestItems[_chestId][_itemIndex].quantity = _chestItem.quantity;
        }
        if (nftChestItems[_chestId][_itemIndex].edition != _chestItem.edition) {
            nftChestItems[_chestId][_itemIndex].edition = _chestItem.edition;
        }
        if (
            nftChestItems[_chestId][_itemIndex].subEdition !=
            _chestItem.subEdition
        ) {
            nftChestItems[_chestId][_itemIndex].subEdition = _chestItem
                .subEdition;
        }
        if (nftChestItems[_chestId][_itemIndex].rarity != _chestItem.rarity) {
            nftChestItems[_chestId][_itemIndex].rarity = _chestItem.rarity;
        }
        if (
            nftChestItems[_chestId][_itemIndex].tradeable !=
            _chestItem.tradeable
        ) {
            nftChestItems[_chestId][_itemIndex].tradeable = _chestItem
                .tradeable;
        }

        emit UpdatedNFTChestItem(
            _chestId,
            _itemIndex,
            _chestItem.nftAddress,
            _chestItem.chance,
            _chestItem.quantity,
            _chestItem.edition,
            _chestItem.subEdition,
            _chestItem.rarity,
            _chestItem.tradeable,
            uint64(block.timestamp)
        );
    }

    function mintNftChestTo(
        uint256 _chestId,
        address _receiver
    ) public gameMasterOnly {
        require(nftChests[_chestId].active, "E7004");
        arcusChest.mint(_receiver, _chestId);
    }

    function mintNftChestToBatch(
        uint256 _chestId,
        address[] memory _receivers
    ) public gameMasterOnly {
        require(nftChests[_chestId].active, "E7004");
        require(_receivers.length <= 10, "E3503");
        for (uint256 i = 0; i < _receivers.length; i++) {
            mintNftChestTo(_chestId, _receivers[i]);
        }
    }
}
