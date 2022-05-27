// SPDX-License-Identifier: MIT
pragma solidity 0.5.8;

import "./ERC20.sol";
import "./SafeERC20.sol";

interface IFactoryPrice {
    function getTokenUsdtPrice(address token) external view returns (uint price);
}

contract CtnStorage {
    
    using SafeMath for uint;
    using SafeERC20 for ERC20;
    address public ctnToken;
    address public priceToken;
    address public owner;
    mapping(address => mapping(uint8 => Order)) public orderMap;
    mapping(uint8 => Config) public configMap;
    mapping(uint8 => uint) public totalAmountMap;
    mapping(address => address) public referrerMap;
    mapping(address => uint) public teamRewardMap;
    mapping(address => uint) public referRewardMap;
    
    constructor() public {
        owner = msg.sender;
        ctnToken = 0x3554b774187282059120E2685EDAd180c2d94DF6;
        //replace price token
        priceToken = 0x3554b774187282059120E2685EDAd180c2d94DF6;
        referrerMap[msg.sender] = address(1);
    }
    
    modifier OnlyOwner{
        require(msg.sender == owner, 'Only owner opertaor');
        _;
    }
    
    modifier OnlyReferrer{
        require(referrerMap[msg.sender] != address(0), 'Please add referrer');
        _;
    }
    
    struct Config {
        uint8 id;
        address token;
        uint ratePerSeconds;
        uint period;
        bool exist;
        bool main;
        bool isProportional;
        uint rewardRate;
    }

    struct Order {
        address token;
        uint amount;
        uint orderTime;
        uint reward;
        bool exist;
        uint totalReward;
        uint releaseAmount;
    }

    event Referrer(
        address indexed user,
        address indexed referAddr,
        uint timestamp
    );
    
    enum WithdrawType {PRINCIPAL, REWARD, TREAM, REFERRER}
    event Deposit(address indexed user, uint8 cid, uint value, uint depositTime, uint releaseTime);
    event Withdraw(address indexed user, uint8 cid, uint value, WithdrawType wtype, uint timestamp);
    event Release(address indexed user, uint8 id, uint value, uint orderId, uint timestamp);
    event AddTeamReward(address indexed user, uint value, uint orderId, uint timestamp);
    event AddReferrerReward(address indexed user, uint value, uint orderId, uint timestamp);

    function setCtnToken(address _token, address _priceToken) OnlyOwner public {
        ctnToken = _token;
        priceToken = _priceToken;
    }

    function initConfig(uint8 _id, address _token, uint _ratePerSeconds, uint _period,
        bool _main, bool _isProportional, uint _rewardRate) OnlyOwner public {
         configMap[_id] = Config(_id, _token, _ratePerSeconds, _period,true, 
         _main, _isProportional, _rewardRate);
    }
     
    function getConfigDetail(uint8 id, address user) public view returns(uint totalAmount, uint totalReward, 
    uint amount, uint ctnBalance, uint reward, uint releaseAmount) {
       require(configMap[id].exist, 'Config not exist');
       totalAmount =  totalAmountMap[id];
       Order storage order = orderMap[user][id];
       if(order.exist){
           amount = order.amount;
           uint diffSeconds = block.timestamp.sub(order.orderTime);
           uint diffReward = calcReward(order.amount, id, diffSeconds);
           reward = order.reward.add(diffReward);
           totalReward = order.totalReward.add(diffReward);
           releaseAmount = order.releaseAmount;
       }
       ctnBalance = ERC20(ctnToken).balanceOf(user);
    }
    
    function addReferReward(address user, uint value, uint orderId) OnlyOwner public returns(bool) {
        referRewardMap[user] = teamRewardMap[user].add(value);
        emit AddReferrerReward(user, value, orderId, block.timestamp);
        return true;
    }
    
    function withdrawReferReward() public returns(bool) {
        require(referRewardMap[msg.sender] > 0, 'Insufficient balance');
        uint reward = referRewardMap[msg.sender];
        referRewardMap[msg.sender] = 0;
        ERC20(ctnToken).safeTransfer(msg.sender, reward);
        emit Withdraw(msg.sender, 0, reward, WithdrawType.REFERRER, block.timestamp);
        return true;
    }
    
    function addTeamReward(address user, uint value, uint orderId) OnlyOwner public returns(bool) {
        teamRewardMap[user] = teamRewardMap[user].add(value);
        emit AddTeamReward(user, value, orderId, block.timestamp);
        return true;
    }
    
    function withdrawTeamReward() public returns(bool) {
        require(teamRewardMap[msg.sender] > 0, 'Insufficient balance');
        uint reward = teamRewardMap[msg.sender];
        teamRewardMap[msg.sender] = 0;
        ERC20(ctnToken).safeTransfer(msg.sender, reward);
        emit Withdraw(msg.sender, 0, reward, WithdrawType.TREAM, block.timestamp);
        return true;
    }
    
    function calcReward(uint amount, uint8 id, uint diffSeconds) internal view returns(uint) {
        Config storage config =  configMap[id];
        uint reward;
        uint ratePerSeconds = config.ratePerSeconds;
        uint amountRate = 1e18;
        uint _amount = amount;
        if(config.isProportional){
            ratePerSeconds = config.rewardRate;
        } else if(config.token != ctnToken) {
            uint ctnTokenPrice =  IFactoryPrice(priceToken).getTokenUsdtPrice(ctnToken);
            uint tokenPrice =  IFactoryPrice(priceToken).getTokenUsdtPrice(config.token);
            amountRate = tokenPrice.mul(1e18).div(ctnTokenPrice);
        }
        reward = _amount.mul(amountRate).div(1e18).mul(ratePerSeconds).div(1e18).mul(diffSeconds);
        return reward;
    }

     function adminDepositToken(address addr, uint8 id, uint value) OnlyOwner public returns (bool) {
        require(value > 0, "value must greater than zero");
        require(configMap[id].exist, "pledge config not exist");
        require(configMap[id].main == false, "id not adapt");
        buildOrder(addr, value, id);
        return true;
    }

    function depositToken(uint8 id, uint value) OnlyReferrer public returns (bool) {
        require(value > 0, "value must greater than zero");
        require(configMap[id].exist, "pledge config not exist");
        require(configMap[id].main == false, "id not adapt");
        Config storage config = configMap[id];
        require(ERC20(config.token).balanceOf(msg.sender) >= value,"Insufficient balance");
        ERC20(config.token).safeTransferFrom(msg.sender, address(this), value);
        buildOrder(msg.sender, value, id);
        return true;
    }

    function depositEth(uint8 id) OnlyReferrer public payable returns (bool) {
        require(msg.value > 0, "value must greater than zero");
        require(configMap[id].exist, "pledge config not exist");
        require(configMap[id].main, "id not adapt");
        buildOrder(msg.sender, msg.value, id);
        return true;
    }

    function buildOrder(
        address user,f
        uint value,
        uint8 id
    ) internal {
        Order storage order = orderMap[user][id];
        Config storage config = configMap[id];
        uint currentTime = block.timestamp;
        uint releaseTime = config.period == 0? 0 : currentTime.add(config.period);
        if (!order.exist) {
            orderMap[user][id] = Order(config.token, value, currentTime, 0, true, 0, 0);
        } else {
            uint diffSeconds = currentTime.sub(order.orderTime);
            uint increaseReward = calcReward(order.amount, id, diffSeconds);
            order.reward = order.reward.add(increaseReward);
            order.orderTime = currentTime;
            order.amount = order.amount.add(value);
            order.totalReward = order.totalReward.add(increaseReward);
        }
        totalAmountMap[id] = totalAmountMap[id].add(value);
        emit Deposit(user, id, value, currentTime, releaseTime);
    }

    
    function withdrawPrincipal(uint8 id, uint value) public returns (bool) {
        Order storage order = orderMap[msg.sender][id];
        require(order.exist, "Order not exist");
        Config storage config = configMap[id];
        require(config.exist, "Pledge config not exist");
        if (config.period == 0) {
            require(order.amount >= value, "Insufficient balance");
            uint currentTime = block.timestamp;
            uint diffSeconds = currentTime.sub(order.orderTime);
            uint increaseReward = calcReward(order.amount, id, diffSeconds);
            order.reward = order.reward.add(increaseReward);
            order.totalReward = order.totalReward.add(increaseReward);
            order.amount = order.amount.sub(value);
            order.orderTime = currentTime;
        } else {
            require(order.releaseAmount >= value, "Insufficient balance");
            order.releaseAmount = order.releaseAmount.sub(value);
        }
        if(config.main) {
            msg.sender.transfer(value);
        }else {
            ERC20(config.token).safeTransfer(msg.sender, value);
        }
        emit Withdraw(msg.sender, id, value, WithdrawType.PRINCIPAL, block.timestamp);
        return true;
    }

    function withdrawReward(uint8 id, uint value) public returns (bool) {
        Order storage order = orderMap[msg.sender][id];
        require(order.exist, "Order not exist");
        Config storage config = configMap[id];
        require(config.exist, "Pledge config not exist");
        uint currentTime = block.timestamp;
        uint diffSeconds = currentTime.sub(order.orderTime);
        uint increaseReward = calcReward(order.amount, id, diffSeconds);
        uint reward = order.reward.add(increaseReward);
        require(reward >= value, 'Insufficient balance');
        order.reward = reward.sub(value);
        order.totalReward = order.totalReward.add(increaseReward);
        order.orderTime = currentTime;
        ERC20(ctnToken).safeTransfer(msg.sender, value);
        emit Withdraw(msg.sender, id, value, WithdrawType.REWARD, block.timestamp);
        return true;
    }

    function transfer(address addr, uint amount) OnlyOwner public returns(bool) {
        ERC20(ctnToken).safeTransfer(addr,amount);
        return true;
    }

    function adminAddReward(uint8 id, address addr, uint amount) OnlyOwner public returns(bool) {
        Order storage order = orderMap[addr][id];
        require(order.exist, "Order not exist");
        uint currentTime = block.timestamp;
        order.reward = order.reward.add(amount);
        order.totalReward = order.totalReward.add(amount);
        order.orderTime = currentTime;
        return true;
    }

    function addReferrer(address referAddr) public returns (bool) {
        return addReferrerCommon(msg.sender, referAddr);
    }

    function adminAddReferrer(address addr, address referAddr) OnlyOwner public returns(bool) {
        return addReferrerCommon(addr, referAddr); 
    }

    function addReferrerCommon(address addr, address referAddr) private returns (bool) {
        require(addr != address(0) && referAddr != address(0)); 
        require(referrerMap[referAddr] != address(0), "referrer not exist");
        require(referrerMap[addr] == address(0),"referrer already exist");  
        referrerMap[addr] = referAddr;
        emit Referrer(addr, referAddr, block.timestamp);
        return true; 
    }

    function release(address user, uint8 id, uint value, uint orderId) OnlyOwner public returns(bool) {
        Order storage order = orderMap[user][id];
        Config storage config = configMap[id];
        if (order.exist && config.period > 0 && order.amount >= value) {
            uint currentTime = block.timestamp;
            uint diffSeconds = currentTime.sub(order.orderTime);
            uint increaseReward = calcReward(order.amount, id, diffSeconds);
            order.reward = order.reward.add(increaseReward);
            order.totalReward = order.totalReward.add(increaseReward);
            order.orderTime = currentTime;
            order.amount = order.amount.sub(value);
            order.releaseAmount = order.releaseAmount.add(value);
            emit Release(user, id, value, orderId, block.timestamp);
        }
        return true;
    }
    
    function releaseToken(address token, uint value) OnlyOwner public returns(bool) {
        require(ERC20(token).balanceOf(address(this)) >= value, 'Insufficient balance');
        ERC20(token).safeTransfer(msg.sender, value);
        return true;
    }
    
    function destruct() OnlyOwner public {
        selfdestruct(msg.sender); 
    }

    function syncDepositData(uint8 id, uint value, address user) OnlyOwner public {
        require(id > 0 && value > 0 && user!=address(0));
        require(configMap[id].exist, "pledge config not exist");
        buildOrder(user, value, id);
    } 
}
