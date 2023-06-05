// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./RoundManager.sol";
import "./WhitelistManager.sol";
import "./ArcusWarrior.sol";
import "./ArcusEther.sol";
import "./ArcusWeapon.sol";
import "./interfaces/IArcusNFT.sol";
import "./interfaces/ICrystalToken.sol";

contract Arcus is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20;
    using SafeERC20Upgradeable for ICrystalToken;

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");
    uint256 public constant MAX_BATCH_MINT = 10;

    CountersUpgradeable.Counter private currentRound;

    uint256 private currentMaxIndex;
    address public treasury;

    ICrystalToken public crystalToken;

    RoundManager public roundManager;
    WhitelistManager public whitelistManager;
    ArcusWarrior public arcusWarrior;
    ArcusEther public arcusEther;
    ArcusWeapon public arcusWeapon;

    mapping(address => uint256) public userScrolls;
    mapping(uint256 => uint256) public nftPrices; //index => price

    uint256 public rewardCenterRarity;

    event CrystalConverted(
        address indexed user,
        uint256 amount,
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

    function _canMint(
        uint256 _limit,
        uint256 _userLimit,
        bool _whitelistOnly,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _round,
        uint256 _index,
        uint256 _amount
    ) private view returns (bool, string memory) {
        bool canMint = true;
        if (_limit > 0) {
            canMint = roundManager.getRoundMints(_round).add(_amount) <= _limit;
            if (!canMint) {
                return (canMint, "E3007");
            }
        }
        if (_userLimit > 0) {
            canMint =
                roundManager.getRoundUserMints(_round, msg.sender, _index).add(
                    _amount
                ) <=
                _userLimit;
            if (!canMint) {
                return (canMint, "E3009");
            }
        }
        if (_whitelistOnly) {
            canMint =
                whitelistManager.balanceOf(msg.sender, _tokenId) >= _amount;
            if (!canMint) {
                return (canMint, "E3003");
            }
        }
        if (_price > 0) {
            canMint =
                IERC20(_paymentToken).balanceOf(msg.sender) >
                _price.mul(_amount);
            if (!canMint) {
                return (canMint, "E3002");
            }
        }
        return (canMint, "");
    }

    function _mintNft(
        address _minter,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity,
        uint256 _index,
        uint256 _amount
    ) private {
        if (_index == 1) {
            arcusWarrior.mintN(_minter, _edition, _subEdition, _rarity, _amount);
        } else if (_index == 2) {
            arcusEther.mintN(_minter, _edition, _subEdition, _rarity, _amount);
        } else if (_index == 3) {
            arcusWeapon.mintN(_minter, _edition, _subEdition, _rarity, _amount);
        }
    }

    function initialize(
        address _treasury,
        RoundManager _roundManager,
        WhitelistManager _whitelistManager,
        ArcusWarrior _arcusWarrior,
        ArcusEther _arcusEther,
        ArcusWeapon _arcusWeapon
    ) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAME_MASTER, msg.sender);

        currentMaxIndex = 3;

        treasury = _treasury;
        roundManager = _roundManager;
        whitelistManager = _whitelistManager;
        arcusWarrior = _arcusWarrior;
        arcusEther = _arcusEther;
        arcusWeapon = _arcusWeapon;
    }

    function setRarityForRewardCenter(uint256 _rarity) public gameMasterOnly {
        require(_rarity > 0, "E3011");
        rewardCenterRarity = _rarity;
    }

    function setPriceForRewardCenter(uint256 _index, uint256 _price) public gameMasterOnly {
        require(_index > 0 && _index <= currentMaxIndex, "E3010");
        require(_price > 0, "E5003");
        nftPrices[_index] = _price;
    }

    function setTreasury(address _treasury) public ownerOnly {
        require(_treasury != address(0), "E5006");
        treasury = _treasury;
    }

    function setCrystalToken(ICrystalToken _crystalToken) public gameMasterOnly {
        crystalToken = _crystalToken;
    }

    function mintNft(
        uint256 _round,
        uint256 _index,
        uint256 _amount
    ) public nonReentrant {
        require(_index > 0 && _index <= currentMaxIndex, "E3010");
        require(_amount > 0 && _amount <= MAX_BATCH_MINT, "E5005");
        RoundManager.RoundInfo memory roundInfo = roundManager.getRound(_round);
        require(block.timestamp >= roundInfo.startDate, "E3006");
        uint256 nftPrice = roundManager.getRoundNftPrice(_round, _index);

        (bool canMint, string memory reason) = _canMint(
            roundInfo.limit,
            roundInfo.userLimit,
            roundInfo.whitelistOnly,
            roundInfo.tokenId,
            roundInfo.paymentToken,
            nftPrice,
            _index,
            _round,
            _amount
        );
        require(canMint, reason);

        if (roundInfo.whitelistOnly) {
            whitelistManager.burn(msg.sender, roundInfo.tokenId, _amount);
        }
        if (nftPrice > 0) {
            IERC20(roundInfo.paymentToken).transferFrom(
                msg.sender,
                treasury,
                nftPrice.mul(_amount)
            );
        }
        _mintNft(
            msg.sender,
            roundInfo.edition,
            roundInfo.subEdition,
            roundInfo.rarity,
            _index,
            _amount
        );
        roundManager.increaseRoundUserMints(
            _round,
            msg.sender,
            _index,
            _amount
        );
    }

    function sendScroll(address _user, uint256 _amount) public gameMasterOnly {
        userScrolls[_user] = userScrolls[_user].add(_amount);
    }

    function useScroll(address _nftAddress, uint256 _tokenId) public nonReentrant {
        require(userScrolls[msg.sender] > 0, "E9001");
        uint256 tradeableIndex = IArcusNFT(_nftAddress).TRADEABLE();
        require(IArcusNFT(_nftAddress).getNftVars(_tokenId, tradeableIndex) == 0, "E9002");
        userScrolls[msg.sender] = userScrolls[msg.sender].sub(1);
        IArcusNFT(_nftAddress).setNftVars(_tokenId, tradeableIndex, 1);
    }

    function convertCrystal(address _user, uint256 _amount) public gameMasterOnly {
        crystalToken.mint(_user, _amount);
        emit CrystalConverted(_user, _amount, uint64(block.timestamp));
    }

    function mintCrystalBatchTo(address[] memory tos, uint256[] memory amounts) public gameMasterOnly {
        require(tos.length == amounts.length, "E3501");
        for (uint256 i = 0; i < amounts.length; i++) {
            crystalToken.mint(tos[i], amounts[i]);
        }
    }

    function mintNftToBatch(
        uint256 _index,
        uint256 _edition,
        uint256 _subEdition,
        uint256 _rarity,
        address[] memory _receivers
    ) public gameMasterOnly {
        require(_receivers.length <= 10, "E3503");
        for (uint256 i = 0; i < _receivers.length; i++) {
            _mintNft(_receivers[i], _edition, _subEdition, _rarity, _index, 1);
        }
    }

    function mintUsingCrystal(uint256 _index, uint256 _amount) public nonReentrant {
        require(_amount > 0, "E5005");
        require(_index > 0 && _index <= currentMaxIndex, "E3010");
        require(rewardCenterRarity > 0 && nftPrices[_index] > 0, "E3012");
        require(crystalToken.balanceOf(msg.sender) >= nftPrices[_index] * _amount, "E3013");        
        _mintNft(msg.sender, 4, 0, rewardCenterRarity, _index, _amount);
        crystalToken.burnFrom(
            msg.sender,
            nftPrices[_index] * _amount
        );
    }
}
