// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "chainlink/shared/interfaces/AggregatorV3Interface.sol";
import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { DecentralizedStableCoin } from "src/DecentralizedStableCoin.sol";
import { OracleLib } from "src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    /* ==================== ERRORS ============================================================ */
    error DSCEngine__TokenAddressesAndTokenDecimalsAmountsDontMatch();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__TokenDecimalsGreaterThan18();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /* ==================== TYPES ============================================================ */
    using OracleLib for AggregatorV3Interface;

    /* ==================== STATE VARIABLES ============================================================ */
    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 200; // you need to be at least 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means liquidators get 10% of the liquidated assets
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint8 private constant DEFAULT_TOKEN_DECIMALS = 18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address token => uint8 decimals) private s_decimals;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] private s_collateralTokens;

    /* ==================== EVENTS ============================================================ */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    // if from != to, then it was liquidated
    event CollateralRedeemed(address indexed from, address indexed to, address token, uint256 amount);

    /* ==================== MODIFIERS ============================================================ */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    /* ==================== CONSTRUCTOR ============================================================ */
    constructor(
        address[] memory tokenAddresses,
        uint8[] memory tokenDecimals,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != tokenDecimals.length) {
            revert DSCEngine__TokenAddressesAndTokenDecimalsAmountsDontMatch();
        }
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenDecimals[i] > DEFAULT_TOKEN_DECIMALS) {
                revert DSCEngine__TokenDecimalsGreaterThan18();
            }
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_decimals[tokenAddresses[i]] = tokenDecimals[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /* ==================== EXTERNAL FUNCTIONS ============================================================ */
    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    // nonReentrant modifier is used
    // slither-disable-next-line reentrancy-events
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToBurn)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amount: The amount of DSC the caller wants to burn from their own balance.
     * @notice careful! You'll burn your DSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * your DSC but keep your collateral in.
     */
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're using
     * to make the protocol solvent again.
     * This is the collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a health factor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized
     * in order for this to work.
     * @notice A known bug would be if the protocol was only 100% collateralized,
     * we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * TODO implement a feature to liquidate in the event the protocol is insolvent
     * and sweep extra amounts into a treasury
     */
    // nonReentrant modifier is used
    // slither-disable-next-line reentrancy-no-eth
    function liquidate(
        address tokenCollateralAddress,
        address user,
        uint256 debtToCover
    )
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need $100 of collateral
        uint256 amountCollateral = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        // And give liquidators a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        uint256 bonusCollateral = (amountCollateral * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // redeem 110% collateral from user to liquidator
        _redeemCollateral(tokenCollateralAddress, amountCollateral + bonusCollateral, user, msg.sender);
        // burn DSC from liquidator, and decrement user debt
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /* ==================== PUBLIC FUNCTIONS ============================================================ */
    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral to deposit
     * @param amountCollateral: The amount of collateral to deposit
     * @notice Pulls `amountCollateral` of `tokenCollateralAddress` from the caller and credits it against
     * their position. Reverts if the token is not whitelisted. Does not change DSC supply.
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param amountDscToMint: The amount of DSC to mint
     * @notice Mints `amountDscToMint` of DSC to the caller. Reverts if the resulting position would
     * fall below `MIN_HEALTH_FACTOR` — you can only mint DSC if you have enough collateral.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /* ==================== PRIVATE FUNCTIONS ======================================== */
    /**
     * @dev Low-level private function. Only call this if the calling function checks for broken health factor.
     */
    function _redeemCollateral(address token, uint256 amount, address from, address to) private {
        s_collateralDeposited[from][token] -= amount;
        emit CollateralRedeemed(from, to, token, amount);
        bool success = IERC20(token).transfer(to, amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev Low-level private function. Only call this if the calling function checks for broken health factor.
     */
    function _burnDsc(uint256 amount, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amount;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    /* ==================== PRIVATE & INTERNAL VIEW & PURE FUNCTIONS ======================================== */
    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // we use only the return value we are interested in
        // slither-disable-next-line unused-return
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // Token amounts are not always in 1e18 precision
        // We assume there is no token with more than 18 decimals
        uint256 additionalAmountPrecision = 10 ** (DEFAULT_TOKEN_DECIMALS - s_decimals[token]);
        // The returned value from Chainlink will be in 1e8 precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we multiply be 1e10
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount * additionalAmountPrecision) / PRECISION;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getTotalCollateralValueInUsd(user);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 totalCollateralValueInUsd
    )
        private
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD;
        // the divided value was previously multplied by a precision variable
        // slither-disable-next-line divide-before-multiply
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /* ==================== PUBLIC & EXTERNAL VIEW & PURE FUNCTIONS ======================================== */
    function getTotalCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 collateralTokensLength = s_collateralTokens.length;
        for (uint256 index = 0; index < collateralTokensLength; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // we use only the return value we are interested in
        // slither-disable-next-line unused-return
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // We must return the amount in the token's precison
        uint256 tokenPrecision = 10 ** s_decimals[token];
        return ((usdAmount * tokenPrecision) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getTokenDecimals(address token) external view returns (uint8) {
        return s_decimals[token];
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 totalCollateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getDefaultTokenDecimals() external pure returns (uint256) {
        return DEFAULT_TOKEN_DECIMALS;
    }

    function getCollateralBalance(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralValueInUsd(address user, address token) external view returns (uint256) {
        return _getUsdValue(token, s_collateralDeposited[user][token]);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
