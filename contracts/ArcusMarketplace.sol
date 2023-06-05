// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract ArcusMarketplace is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable,
    IERC1155ReceiverUpgradeable
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

    struct NFTMarketList {
        address paymentToken;
        uint256 tokenId;
        address seller;
        uint256 price;
        uint256 totalPrice;
        uint256 amount;
        uint64 timestamp;
        bool listed;
    }

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");

    uint64 public constant MAX_FEE = 10_000;

    EnumerableSet.AddressSet private allowedPaymentTokens;
    EnumerableSet.AddressSet private allowedNFTs;

    address public treasury;
    uint64 public platformFee;
    bool public isRoyaltyEnable;

    uint256 public totalPlatformFee;
    uint256 public totalNftSold;

    mapping(address => TokenType) tokenTypes;
    mapping(address => mapping(uint256 => NFTMarketList)) public marketList;
    mapping(address => EnumerableSet.UintSet) listedTokenIds;

    event NFTListCreated(
        uint256 tokenId,
        address indexed seller,
        address indexed nftAddress,
        address indexed paymentToken,
        uint256 price,
        uint256 amount,
        uint64 timestamp
    );

    event NFTListSold(
        uint256 tokenId,
        address indexed seller,
        address buyer,
        address indexed nftAddress,
        address indexed paymentToken,
        uint256 price,
        uint256 amount,
        uint64 timestamp
    );

    event NFTListCanceled(uint256 indexed tokenId, uint64 timestamp);

    modifier ownerOnly() {
        _isOwner();
        _;
    }
    modifier gameMasterOnly() {
        _isGameMaster();
        _;
    }
    modifier validAmount(uint256 _amount) {
        _validAmount(_amount);
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
    modifier isListed(address _nftAddress, uint256 _tokenId) {
        _isListed(_nftAddress, _tokenId);
        _;
    }
    modifier isNotListed(address _nftAddress, uint256 _tokenId) {
        _isNotListed(_nftAddress, _tokenId);
        _;
    }

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function _validAmount(uint256 _amount) private pure {
        require(_amount > 0, "E5005");
    }

    function _nftCollectionAllowed(address _nftAddress) private view {
        require(allowedNFTs.contains(_nftAddress), "E4002");
    }

    function _paymentTokenAllowed(address _paymentToken) private view {
        require(allowedPaymentTokens.contains(_paymentToken), "E2001");
    }

    function _isListed(address _tokenAddress, uint256 _tokenId) private view {
        require(listedTokenIds[_tokenAddress].contains(_tokenId), "E5002");
    }

    function _isNotListed(address _tokenAddress, uint256 _tokenId)
        private
        view
    {
        require(!listedTokenIds[_tokenAddress].contains(_tokenId), "E5002");
    }

    function initialize(
        address _basePaymentToken,
        address _treasury,
        uint64 _platformFee,
        bool _isRoyaltyEnable
    ) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_MASTER, msg.sender);

        allowedPaymentTokens.add(_basePaymentToken);
        treasury = _treasury;
        platformFee = _platformFee;
        isRoyaltyEnable = _isRoyaltyEnable;
    }

    function setTreasury(address _treasury) public ownerOnly {
        require(_treasury != address(0), "E5006");
        treasury = _treasury;
    }

    function setPlatformFee(uint64 _fee) public ownerOnly {
        require(_fee > 0 && _fee <= MAX_FEE, "E5009");
        platformFee = uint64(uint256(_fee).mul(MAX_FEE).div(100));
    }

    function enableRoyalty(bool _enable) public gameMasterOnly {
        isRoyaltyEnable = _enable;
    }

    function addAllowedPaymentToken(address _paymentToken)
        external
        gameMasterOnly
    {
        require(!allowedPaymentTokens.contains(_paymentToken), "E2002");
        allowedPaymentTokens.add(_paymentToken);
    }

    function removeAllowedPaymentToken(address _paymentToken)
        external
        gameMasterOnly
        paymentTokenAllowed(_paymentToken)
    {
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

    function removeAllowedNft(address _nftAddress)
        external
        gameMasterOnly
        nftCollectionAllowed(_nftAddress)
    {
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

    function getTokenType(address _nftAddress)
        internal
        view
        returns (TokenType tokenType)
    {
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

    function listNft(
        address _nftAddress,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _amount
    )
        public
        nonReentrant
        validAmount(_amount)
        nftCollectionAllowed(_nftAddress)
        isNotListed(_nftAddress, _tokenId)
    {
        require(allowedPaymentTokens.contains(_paymentToken), "E2001");
        require(_price > 0, "E5003");
        if (tokenTypes[_nftAddress] == TokenType.ERC721) {
            IERC721Upgradeable nftContract = IERC721Upgradeable(_nftAddress);
            require(nftContract.ownerOf(_tokenId) == msg.sender, "E5001");
            marketList[_nftAddress][_tokenId] = NFTMarketList(
                _paymentToken,
                _tokenId,
                msg.sender,
                _price,
                _price.mul(_amount),
                1,
                uint64(block.timestamp),
                true
            );
            nftContract.safeTransferFrom(msg.sender, address(this), _tokenId);
        } else {
            IERC1155Upgradeable nftContract = IERC1155Upgradeable(_nftAddress);
            require(nftContract.balanceOf(msg.sender, _tokenId) != 0, "E5001");
            require(
                _amount <= nftContract.balanceOf(msg.sender, _tokenId),
                "E5005"
            );
            marketList[_nftAddress][_tokenId] = NFTMarketList(
                _paymentToken,
                _tokenId,
                msg.sender,
                _price,
                _price.mul(_amount),
                _amount,
                uint64(block.timestamp),
                true
            );
            nftContract.safeTransferFrom(
                msg.sender,
                address(this),
                _tokenId,
                _amount,
                ""
            );
        }
        listedTokenIds[_nftAddress].add(_tokenId);
        emit NFTListCreated(
            _tokenId,
            msg.sender,
            _nftAddress,
            _paymentToken,
            _price,
            _amount,
            uint64(block.timestamp)
        );
    }

    function buyNft(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _amount
    )
        public
        nonReentrant
        validAmount(_amount)
        nftCollectionAllowed(_nftAddress)
        isListed(_nftAddress, _tokenId)
    {
        NFTMarketList memory marketInfo = marketList[_nftAddress][_tokenId];
        IERC20 payToken = IERC20(marketInfo.paymentToken);
        uint256 totalPrice = marketInfo.price.mul(_amount);
        require(payToken.balanceOf(msg.sender) >= totalPrice, "E3002");

        if (tokenTypes[_nftAddress] == TokenType.ERC721) {
            require(_amount == 1, "E5005");
        }
        require(_checkOwnership(_nftAddress, _tokenId, msg.sender), "E5004");

        _executePayment(
            _nftAddress,
            _tokenId,
            payToken,
            msg.sender,
            marketInfo.seller,
            marketInfo.price,
            _amount
        );
        _transferNft(_nftAddress, address(this), msg.sender, _tokenId, _amount);

        totalNftSold = totalNftSold.add(_amount);
        if (_amount < marketInfo.amount) {
            marketList[_nftAddress][_tokenId].amount = marketInfo.amount.sub(
                _amount
            );
        } else {
            delete marketList[_nftAddress][_tokenId];
            listedTokenIds[_nftAddress].remove(_tokenId);
        }
        emit NFTListSold(
            _tokenId,
            marketInfo.seller,
            msg.sender,
            _nftAddress,
            marketInfo.paymentToken,
            marketInfo.price,
            _amount,
            uint64(block.timestamp)
        );
    }

    function _checkOwnership(
        address _nftAddress,
        uint256 _tokenId,
        address _user
    ) private view returns (bool) {
        if (tokenTypes[_nftAddress] == TokenType.ERC721) {
            return IERC721Upgradeable(_nftAddress).ownerOf(_tokenId) != _user;
        } else {
            return
                IERC1155Upgradeable(_nftAddress).balanceOf(
                    msg.sender,
                    _tokenId
                ) == 0;
        }
    }

    function _transferNft(
        address _nftAddress,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) private {
        if (tokenTypes[_nftAddress] == TokenType.ERC721) {
            IERC721Upgradeable(_nftAddress).safeTransferFrom(
                _from,
                _to,
                _tokenId
            );
        } else {
            IERC1155Upgradeable(_nftAddress).safeTransferFrom(
                _from,
                _to,
                _tokenId,
                _amount,
                ""
            );
        }
    }

    function _executePayment(
        address _nftAddress,
        uint256 _tokenId,
        IERC20 _paytoken,
        address _from,
        address _to,
        uint256 _price,
        uint256 _amount
    ) internal {
        uint256 totalPrice = _price.mul(_amount);
        uint256 platformFeeCut = (totalPrice.mul(platformFee)).div(MAX_FEE);
        uint256 royaltyFee;
        address royaltyRecipient;

        if (isRoyaltyEnable) {
            try
                IERC2981Upgradeable(_nftAddress).royaltyInfo(
                    _tokenId,
                    totalPrice
                )
            returns (address royaltyFeeRecipient, uint256 royaltyFeeAmount) {
                if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                    require(
                        royaltyFeeAmount.add(platformFeeCut) < totalPrice,
                        "E5008"
                    );
                    royaltyFee = royaltyFeeAmount;
                    royaltyRecipient = royaltyFeeRecipient;
                }
            } catch {}
        }
        _paytoken.transferFrom(
            _from,
            _to,
            totalPrice.sub(platformFeeCut).sub(royaltyFee)
        );
        _paytoken.transferFrom(_from, treasury, platformFeeCut);
        if (royaltyFee > 0) {
            _paytoken.transferFrom(_from, royaltyRecipient, royaltyFee);
        }

        totalPlatformFee = totalPlatformFee.add(platformFeeCut);
    }

    function cancelNftListing(address _nftAddress, uint256 _tokenId)
        public
        nonReentrant
        nftCollectionAllowed(_nftAddress)
        isListed(_nftAddress, _tokenId)
    {
        NFTMarketList memory marketInfo = marketList[_nftAddress][_tokenId];
        require(marketInfo.seller == msg.sender, "E5001");

        _transferNft(
            _nftAddress,
            address(this),
            msg.sender,
            _tokenId,
            marketInfo.amount
        );
        delete marketList[_nftAddress][_tokenId];
        listedTokenIds[_nftAddress].remove(_tokenId);
        emit NFTListCanceled(_tokenId, uint64(block.timestamp));
    }

    function getNftListingIds(address _nftAddress)
        public
        view
        returns (uint256[] memory)
    {
        EnumerableSet.UintSet storage set = listedTokenIds[_nftAddress];
        uint256[] memory tokens = new uint256[](set.length());

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = set.at(i);
        }
        return tokens;
    }

    function getTotalNftListingCount() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < allowedNFTs.length(); i++) {
            total = total.add(listedTokenIds[allowedNFTs.at(i)].length());
        }
        return total;
    }

    function getNftListingCount(address _nftAddress)
        public
        view
        returns (uint256)
    {
        return listedTokenIds[_nftAddress].length();
    }

    function getNftTotalPrice(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _amount
    ) public view returns (uint256) {
        NFTMarketList memory nftMarketInfo = marketList[_nftAddress][_tokenId];
        return nftMarketInfo.price.mul(_amount);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155ReceiverUpgradeable).interfaceId ||
            interfaceId == type(IERC721ReceiverUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
