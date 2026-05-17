import { Minted } from "../generated/ProtocolNFT/ProtocolNFT";
import { NFTMint } from "../generated/schema";

export function handleMinted(event: Minted): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let mint = new NFTMint(id);
  mint.to = event.params.to;
  mint.tokenId = event.params.tokenId;
  mint.uri = event.params.uri;
  mint.timestamp = event.block.timestamp;
  mint.blockNumber = event.block.number;
  mint.save();
}
