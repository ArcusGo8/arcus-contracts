// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RoundManager is Initializable, AccessControlUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMath for uint256;

    struct RoundInfo {
        uint64 startDate;
        uint256 tokenId;
        uint256 edition;
        uint256 subEdition;
        uint256 rarity;
        uint256 limit;
        uint256 userLimit;
        address paymentToken;
        bool whitelistOnly;
        bool exist;
    }

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");

    uint256 public constant WARRIOR_INDEX = 1;
    uint256 public constant ETHER_INDEX = 2;
    uint256 public constant WEAPON_INDEX = 3;

    CountersUpgradeable.Counter private currentRound;

    mapping(uint256 => RoundInfo) rounds;
    mapping(uint256 => uint256) roundMints;
    mapping(uint256 => mapping(uint256 => uint256)) nftPrice; // round => type (1 = warrior, 2 = ether, 3 = weapon) => price
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) userMints; // user => round => type (1 = warrior, 2 = ether, 3 = weapon) => limit

    event RoundStarted(
        uint256 round,
        uint64 indexed startDate,
        uint256 tokenId,
        uint256 indexed edition,
        uint256 subEdition,
        uint256 rarity,
        uint256 limit,
        uint256 userLimit,
        address indexed paymentToken,
        bool whitelistOnly,
        uint256 warriorPrice,
        uint256 etherPrice,
        uint256 weaponPrice
    );

    modifier ownerOnly() {
        _isOwner();
        _;
    }
    modifier gameMasterOnly() {
        _isGameMaster();
        _;
    }
    modifier isRoundExists(uint256 _round) {
        _isRoundExists(_round);
        _;
    }

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function _isRoundExists(uint256 _round) private view {
        require(rounds[_round].exist, "E3008");
    }

    function _updateRound(
        uint256 _round,
        RoundInfo memory _roundInfo,
        uint256 _warriorPrice,
        uint256 _etherPrice,
        uint256 _weaponPrice
    ) private isRoundExists(_round) {
        RoundInfo memory roundInfo = rounds[_round];
        if (roundInfo.startDate != _roundInfo.startDate) {
            require(_roundInfo.startDate > 0, "E3004");
            rounds[_round].startDate = _roundInfo.startDate;
        }
        if (roundInfo.tokenId != _roundInfo.tokenId) {
            rounds[_round].tokenId = _roundInfo.tokenId;
        }
        if (roundInfo.rarity != _roundInfo.rarity) {
            require(_roundInfo.rarity > 0, "E3011");
            rounds[_round].rarity = _roundInfo.rarity;
        }
        if (roundInfo.edition != _roundInfo.edition) {
            require(_roundInfo.edition > 0, "E3005");
            rounds[_round].edition = _roundInfo.edition;
        }
        if (roundInfo.subEdition != _roundInfo.subEdition) {
            rounds[_round].subEdition = _roundInfo.subEdition;
        }
        if (roundInfo.limit != _roundInfo.limit) {
            rounds[_round].limit = _roundInfo.limit;
        }
        if (roundInfo.userLimit != _roundInfo.userLimit) {
            rounds[_round].userLimit = _roundInfo.userLimit;
        }
        if (roundInfo.paymentToken != _roundInfo.paymentToken) {
            rounds[_round].paymentToken = _roundInfo.paymentToken;
        }
        if (nftPrice[_round][WARRIOR_INDEX] != _warriorPrice) {
            nftPrice[_round][WARRIOR_INDEX] = _warriorPrice;
        }
        if (nftPrice[_round][ETHER_INDEX] != _etherPrice) {
            nftPrice[_round][ETHER_INDEX] = _etherPrice;
        }
        if (nftPrice[_round][WEAPON_INDEX] != _weaponPrice) {
            nftPrice[_round][WEAPON_INDEX] = _weaponPrice;
        }
        if (roundInfo.whitelistOnly != _roundInfo.whitelistOnly) {
            rounds[_round].whitelistOnly = _roundInfo.whitelistOnly;
        }
    }

    function _increaseRoundMints(uint256 _round, uint256 _amount) private {
        roundMints[_round] = roundMints[_round].add(_amount);
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAME_MASTER, msg.sender);
    }

    function setRound(
        RoundInfo memory _roundInfo,
        uint256 _warriorPrice,
        uint256 _etherPrice,
        uint256 _weaponPrice
    ) public gameMasterOnly {
        require(_roundInfo.startDate > 0, "E3004");
        require(_roundInfo.edition > 0, "E3005");
        currentRound.increment();
        uint256 round = currentRound.current();
        rounds[round] = RoundInfo(
            _roundInfo.startDate,
            _roundInfo.tokenId,
            _roundInfo.edition,
            _roundInfo.subEdition,
            _roundInfo.rarity,
            _roundInfo.limit,
            _roundInfo.userLimit,
            _roundInfo.paymentToken,
            _roundInfo.whitelistOnly,
            true
        );
        nftPrice[round][WARRIOR_INDEX] = _warriorPrice;
        nftPrice[round][ETHER_INDEX] = _etherPrice;
        nftPrice[round][WEAPON_INDEX] = _weaponPrice;

        emit RoundStarted(
            round,
            _roundInfo.startDate,
            _roundInfo.tokenId,
            _roundInfo.edition,
            _roundInfo.subEdition,
            _roundInfo.rarity,
            _roundInfo.limit,
            _roundInfo.userLimit,
            _roundInfo.paymentToken,
            _roundInfo.whitelistOnly,
            _warriorPrice,
            _etherPrice,
            _weaponPrice
        );
    }

    function updateRound(
        uint256 _round,
        RoundInfo memory _roundInfo,
        uint256 _warriorPrice,
        uint256 _etherPrice,
        uint256 _weaponPrice
    ) public gameMasterOnly {
        _updateRound(
            _round,
            _roundInfo,
            _warriorPrice,
            _etherPrice,
            _weaponPrice
        );
    }

    function getRound(uint256 _round) public view returns (RoundInfo memory) {
        return rounds[_round];
    }

    function getCurrentRound() public view returns (uint256) {
        return currentRound.current();
    }

    function getRoundMints(uint256 _round) public view returns (uint256) {
        return roundMints[_round];
    }

    function increaseRoundUserMints(
        uint256 _round,
        address _user,
        uint256 _index,
        uint256 _amount
    ) external gameMasterOnly {
        userMints[_user][_round][_index] = userMints[_user][_round][_index].add(
            _amount
        );
        _increaseRoundMints(_round, _amount);
    }

    function getPreviousRounds() public view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](currentRound.current());
        uint256 counter = 0;
        for (uint256 i = 1; i <= currentRound.current(); i++) {
            if (rounds[i].exist) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
    }

    function getRoundNftPrice(uint256 _round, uint256 _index)
        public
        view
        returns (uint256)
    {
        return nftPrice[_round][_index];
    }

    function getRoundUserMints(
        uint256 _round,
        address _user,
        uint256 _index
    ) public view returns (uint256) {
        return userMints[_user][_round][_index];
    }
}
