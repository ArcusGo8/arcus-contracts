// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract SeedManager is Initializable, AccessControlUpgradeable {
    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");

    uint256 public currentSeedIndex; // new requests pile up under this index
    uint256 public seedIndexBlockNumber; // the block number "currentSeedIndex" was reached on
    uint256 public firstRequestBlockNumber; // first request block for the latest seed index
    mapping(uint256 => bytes32) public seedHashes; // key: seedIndex

    // keys: user, requestID / value: seedIndex
    mapping(address => mapping(uint256 => uint256)) public singleSeedRequests; // one-at-a-time (saltable)
    mapping(address => mapping(uint256 => uint256)) public singleSeedSalts; // optional, ONLY for single seeds
    mapping(address => mapping(uint256 => uint256[])) public queuedSeedRequests; // arbitrary in/out LIFO

    bool public publicResolutionLimited;
    uint256 public publicResolutionBlocks; // max number of blocks to resolve if limited

    bool public emitResolutionEvent;
    bool public emitRequestEvent;
    bool public emitPopEvent;

    event SeedResolved(address indexed resolver, uint256 indexed seedIndex);
    event SeedRequested(address indexed requester, uint256 indexed requestId);
    event SeedPopped(address indexed popper, uint256 indexed requestId);

    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        currentSeedIndex = 1; // one-at-a-time seeds have a 0 check
        seedIndexBlockNumber = block.number;
        firstRequestBlockNumber = block.number - 1; // save 15k gas for very first user
    }

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

    // SINGLE SEED REQUESTS

    function requestSingleSeed(address user, uint256 requestID)
        public
        gameMasterOnly
    {
        _resolveSeedPublic(user);
        _requestSingleSeedAssert(user, requestID);
    }

    function requestSingleSeed(
        address user,
        uint256 requestID,
        bool force
    ) public gameMasterOnly {
        _resolveSeedPublic(user);
        if (force) _requestSingleSeed(user, requestID);
        else _requestSingleSeedAssert(user, requestID);
    }

    function _requestSingleSeedAssert(address user, uint256 requestID)
        internal
    {
        require(singleSeedRequests[user][requestID] == 0);
        _requestSingleSeed(user, requestID);
    }

    function _requestSingleSeed(address user, uint256 requestID) internal {
        singleSeedRequests[user][requestID] = currentSeedIndex;
        if (firstRequestBlockNumber < seedIndexBlockNumber)
            firstRequestBlockNumber = block.number;

        if (emitRequestEvent) emit SeedRequested(user, requestID);
    }

    // QUEUED SEED REQUESTS

    function requestQueuedSeed(address user, uint256 requestID)
        public
        gameMasterOnly
    {
        _resolveSeedPublic(user);
        _requestQueuedSeed(user, requestID);
    }

    function _requestQueuedSeed(address user, uint256 requestID) internal {
        queuedSeedRequests[user][requestID].push(currentSeedIndex);
        if (firstRequestBlockNumber < seedIndexBlockNumber)
            firstRequestBlockNumber = block.number;

        if (emitRequestEvent) emit SeedRequested(user, requestID);
    }

    // SEED RESOLUTIONS

    function resolveSeedPublic() public {
        _resolveSeedPublic(msg.sender);
    }

    function _resolveSeedPublic(address resolver) internal {
        if (
            !publicResolutionLimited ||
            block.number < firstRequestBlockNumber + publicResolutionBlocks
        ) _resolveSeed(resolver);
    }

    function resolveSeedAdmin() public gameMasterOnly {
        _resolveSeed(msg.sender);
    }

    function _resolveSeed(address resolver) internal {
        if (
            block.number > firstRequestBlockNumber &&
            firstRequestBlockNumber >= seedIndexBlockNumber
        ) {
            seedHashes[currentSeedIndex++] = blockhash(block.number - 1);
            seedIndexBlockNumber = block.number;
            if (emitResolutionEvent)
                emit SeedResolved(resolver, currentSeedIndex);
        }
    }

    // SINGLE SEED FULFILLMENT

    function popSingleSeed(
        address user,
        uint256 requestID,
        bool resolve,
        bool requestNext
    ) public gameMasterOnly returns (uint256 seed) {
        if (resolve) _resolveSeedPublic(user);

        seed = readSingleSeed(user, requestID, false); // reverts on zero
        delete singleSeedRequests[user][requestID];

        if (emitPopEvent) emit SeedPopped(user, requestID);

        if (requestNext) _requestSingleSeed(user, requestID);
    }

    function readSingleSeed(
        address user,
        uint256 requestID,
        bool allowZero
    ) public view returns (uint256 seed) {
        if (seedHashes[singleSeedRequests[user][requestID]] == 0) {
            require(allowZero);
            // seed stays 0 by default if allowed
        } else {
            seed = uint256(
                keccak256(
                    abi.encodePacked(
                        seedHashes[singleSeedRequests[user][requestID]],
                        user,
                        requestID
                    )
                )
            );
        }
    }

    function saltSingleSeed(
        address user,
        uint256 requestID,
        bool resolve
    ) public gameMasterOnly returns (uint256 seed) {
        if (resolve) _resolveSeedPublic(user);

        require(seedHashes[singleSeedRequests[user][requestID]] != 0);
        seed = uint256(
            keccak256(
                abi.encodePacked(
                    seedHashes[singleSeedRequests[user][requestID]],
                    singleSeedSalts[user][requestID]
                )
            )
        );
        singleSeedSalts[user][requestID] = seed;
        return seed;
    }

    // QUEUED SEED FULFILLMENT

    function popQueuedSeed(
        address user,
        uint256 requestID,
        bool resolve,
        bool requestNext
    ) public gameMasterOnly returns (uint256 seed) {
        if (resolve) _resolveSeedPublic(user);

        // will revert on empty queue due to pop()
        seed = readQueuedSeed(user, requestID, false);
        queuedSeedRequests[user][requestID].pop();

        if (emitPopEvent) emit SeedPopped(user, requestID);

        if (requestNext) _requestQueuedSeed(user, requestID);

        return seed;
    }

    function readQueuedSeed(
        address user,
        uint256 requestID,
        bool allowZero
    ) public view returns (uint256 seed) {
        uint256 lastIndex = queuedSeedRequests[user][requestID].length - 1;
        seed = uint256(
            keccak256(
                abi.encodePacked(
                    seedHashes[queuedSeedRequests[user][requestID][lastIndex]],
                    user,
                    requestID,
                    lastIndex
                )
            )
        );
        require(allowZero || seed != 0);
    }

    // HELPER VIEWS

    function hasSingleSeedRequest(address user, uint256 requestID)
        public
        view
        returns (bool)
    {
        return singleSeedRequests[user][requestID] != 0;
    }

    function getQueuedRequestCount(uint256 requestID)
        public
        view
        returns (uint256)
    {
        return queuedSeedRequests[msg.sender][requestID].length;
    }

    function encode(uint256[] calldata requestData)
        external
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(requestData)));
    }

    // ADMIN FUNCTIONS (excluding resolveSeedAdmin)

    function setPublicResolutionLimited(bool to) public gameMasterOnly {
        publicResolutionLimited = to;
    }

    function setPublicResolutionBlocks(uint256 to) public gameMasterOnly {
        publicResolutionBlocks = to;
    }

    function setEmitResolutionEvent(bool to) public gameMasterOnly {
        emitResolutionEvent = to;
    }

    function setEmitRequestEvent(bool to) public gameMasterOnly {
        emitRequestEvent = to;
    }

    function setEmitPopEvent(bool to) public gameMasterOnly {
        emitPopEvent = to;
    }
}
