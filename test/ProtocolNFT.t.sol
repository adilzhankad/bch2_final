// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/ProtocolNFT.sol";

contract ProtocolNFTTest is Test {
    ProtocolNFT internal nft;
    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal MINTER_ROLE;

    function setUp() public {
        nft = new ProtocolNFT(admin, "ipfs://base/");
        MINTER_ROLE = nft.MINTER_ROLE();
        // Cache role bytes before prank to avoid consuming prank on getter call
        vm.prank(admin);
        nft.grantRole(MINTER_ROLE, minter);
    }

    function test_name_symbol() public view {
        assertEq(nft.name(), "ProtocolNFT");
        assertEq(nft.symbol(), "PNFT");
    }

    function test_mint_byMinter() public {
        vm.prank(minter);
        uint256 tokenId = nft.safeMint(alice, "token0");
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_mint_revert_notMinter() public {
        vm.expectRevert();
        vm.prank(alice);
        nft.safeMint(alice, "token0");
    }

    function test_mint_sequential_ids() public {
        vm.startPrank(minter);
        uint256 id0 = nft.safeMint(alice, "a");
        uint256 id1 = nft.safeMint(bob, "b");
        vm.stopPrank();
        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    function test_tokenURI() public {
        vm.prank(minter);
        uint256 id = nft.safeMint(alice, "metadata.json");
        string memory uri = nft.tokenURI(id);
        assertEq(uri, "ipfs://base/metadata.json");
    }

    function test_setBaseURI() public {
        vm.prank(admin);
        nft.setBaseURI("https://new.base/");
        vm.prank(minter);
        uint256 id = nft.safeMint(alice, "x");
        assertEq(nft.tokenURI(id), "https://new.base/x");
    }

    function test_setBaseURI_revert_notAdmin() public {
        vm.expectRevert();
        vm.prank(alice);
        nft.setBaseURI("bad");
    }

    function test_totalSupply_increments() public {
        assertEq(nft.totalSupply(), 0);
        vm.prank(minter);
        nft.safeMint(alice, "a");
        assertEq(nft.totalSupply(), 1);
    }

    function test_transfer() public {
        vm.prank(minter);
        uint256 id = nft.safeMint(alice, "nft");
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);
    }

    function test_supportsInterface_erc721() public view {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
    }

    function test_supportsInterface_erc721Enumerable() public view {
        assertTrue(nft.supportsInterface(type(IERC721Enumerable).interfaceId));
    }

    function test_tokenByIndex() public {
        vm.prank(minter);
        uint256 id = nft.safeMint(alice, "a");
        assertEq(nft.tokenByIndex(0), id);
    }

    function test_maxSupply() public view {
        assertEq(nft.MAX_SUPPLY(), 10_000);
    }

    function test_emitsMinted() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit ProtocolNFT.Minted(alice, 0, "token0");
        nft.safeMint(alice, "token0");
    }

    // ── Fuzz: token IDs are always sequential starting from 0 ────────────────
    function testFuzz_tokenIds_sequential(uint8 count) public {
        // Bound to 1-50 mints to keep runtime reasonable
        count = uint8(bound(count, 1, 50));

        vm.startPrank(minter);
        for (uint256 i = 0; i < count; i++) {
            uint256 id = nft.safeMint(alice, "uri");
            assertEq(id, i, "Token ID must match mint order");
        }
        vm.stopPrank();

        assertEq(nft.totalSupply(), count, "totalSupply must equal number of mints");
    }
}
