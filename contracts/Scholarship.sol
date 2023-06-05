// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./lib/Random.sol";

contract Scholarship is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");
    uint256 internal constant RANDOM_SEED = uint256(keccak256("RANDOM_SEED"));

    uint64 constant MAX_SP = 10_000;
    uint16 constant MAX_UINT = 65_535;

    EnumerableSet.AddressSet managers;

    string private keyHash;

    mapping(address => CountersUpgradeable.Counter) userNonce;
    mapping(address => bool) public activeScholar;
    mapping(address => EnumerableSet.AddressSet) scholarApplications; // manager => players
    mapping(address => EnumerableSet.AddressSet) managerApplications; // player => managers
    mapping(address => EnumerableSet.AddressSet) scholars; // manager => players
    mapping(address => mapping(address => uint64)) public scholarSharePercentage; // manager => player => share
    mapping(address => mapping(address => uint64)) public tempShare; // manager => player => share
    mapping(address => uint256) public pendingReward;
    mapping(address => uint16) private approvalCode; // player => code

    modifier ownerOnly() {
        _isOwner();
        _;
    }
    modifier gameMasterOnly() {
        _isGameMaster();
        _;
    }
    modifier isActiveScholar(address _player) {
        _isActiveScholar(_player);
        _;
    }
    modifier isNotActiveScholar(address _player) {
        _isNotActiveScholar(_player);
        _;
    }
    modifier isActiveManager(address _manager) {
        _isActiveManager(_manager);
        _;
    }
    modifier isNotActiveManager(address _manager) {
        _isNotActiveManager(_manager);
        _;
    }
    modifier isValidShare(uint64 _share) {
        _isValidShare(_share);
        _;
    }
    modifier isNotSelf(address _address) {
        _isNotSelf(_address);
        _;
    }

    function _isOwner() private view {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "E1001");
    }

    function _isGameMaster() private view {
        require(hasRole(GAME_MASTER, msg.sender), "E1002");
    }

    function _isActiveScholar(address _player) private view {
        require(activeScholar[_player], "E8001");
    }

    function _isNotActiveScholar(address _player) private view {
        require(!activeScholar[_player], "E8002");
    }

    function _isActiveManager(address _manager) private view {
        require(managers.contains(_manager), "E8003");
    }

    function _isNotActiveManager(address _manager) private view {
        require(!managers.contains(_manager), "E8004");
    }

    function _isValidShare(uint64 _share) private pure {
        require(_share > 0 && _share <= 100, "E8005");
    }

    function _isNotSelf(address _address) private view {
        require(msg.sender != _address, "E8006");
    }

    function _generateCode(address _user) private returns (uint16) {
        userNonce[_user].increment();
        return
            uint16(
                Random.getRandomSeed(keyHash, _user, userNonce[_user].current()) % MAX_UINT
            );
    }

    function initialize(string memory _keyHash) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_MASTER, msg.sender);

        keyHash = _keyHash;
    }

    function activateManager()
        public
        nonReentrant
        isNotActiveManager(msg.sender)
    {
        managers.add(msg.sender);
    }

    function applyAsScholar(address _manager)
        public
        nonReentrant
        isNotSelf(_manager)
        isActiveManager(_manager)
        isNotActiveScholar(msg.sender)
    {
        scholarApplications[_manager].add(msg.sender);
    }

    function applyAsManager(address _player)
        public
        nonReentrant
        isNotSelf(_player)
        isActiveManager(msg.sender)
        isNotActiveScholar(_player)
    {
        managerApplications[_player].add(msg.sender);
    }

    function setScholarApplicationShare(address _player, uint64 _share)
        public
        nonReentrant
        isActiveManager(msg.sender)
        isValidShare(_share)
    {
        tempShare[msg.sender][_player] = _share;
    }

    function approveScholarShare(address _manager)
        public
        nonReentrant
        isActiveManager(_manager)
    {
        require(tempShare[_manager][msg.sender] > 0, "E8007");
        approvalCode[msg.sender] = _generateCode(msg.sender);
    }

    function approveScholar(address _player, uint16 _approvalCode)
        public
        nonReentrant
        isActiveManager(msg.sender)
        isNotActiveScholar(_player)
    {
        require(approvalCode[_player] == _approvalCode, "");
        require(tempShare[msg.sender][_player] > 0, "E8007");
        scholars[msg.sender].add(_player);
        scholarSharePercentage[msg.sender][_player] = tempShare[msg.sender][_player];
        address[] memory list = getManagerApplications(_player);
        for (uint256 i = 0; i < list.length; i++) {
            managerApplications[_player].remove(list[i]);
        }
        delete tempShare[msg.sender][_player];
        delete approvalCode[_player];
    }

    function approveManager(address _manager)
        public
        nonReentrant
        isActiveManager(_manager)
        isNotActiveScholar(msg.sender)
    {
        require(tempShare[_manager][msg.sender] > 0, "E8007");
        scholars[_manager].add(msg.sender);
        scholarSharePercentage[_manager][msg.sender] = tempShare[_manager][msg.sender];
        address[] memory list = getManagerApplications(msg.sender);
        for (uint256 i = 0; i < list.length; i++) {
            managerApplications[msg.sender].remove(list[i]);
        }
        delete tempShare[_manager][msg.sender];
    }

    function getApprovalCode() public view returns(uint16) {
        return approvalCode[msg.sender];
    }

    function getManagerApplications(address _player)
        public
        view
        returns (address[] memory)
    {
        return managerApplications[_player].values();
    }

    function getScholarApplications(address _manager)
        public
        view
        returns (address[] memory)
    {
        return scholarApplications[_manager].values();
    }

    function getScholars(address _manager)
        public
        view
        returns (address[] memory)
    {
        return scholars[_manager].values();
    }

    function getActiveManagers() public view returns(address[] memory) {
        return managers.values();
    }
}
