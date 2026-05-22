import {
  ProposalCreated,
  VoteCast,
  ProposalCanceled,
  ProposalQueued,
  ProposalExecuted,
} from "../generated/DeFiGovernor/DeFiGovernor";
import { Proposal, Vote } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";

// Subgraph state is a "last known transition" — it's only updated when an event
// fires (creation, vote, queue, execute, cancel). Time-based transitions
// (Pending → Active → Defeated/Succeeded → Expired) cannot be inferred without
// a block handler, so the frontend should fall back to `governor.state(id)` for
// authoritative state. We do compute the time-based Pending/Active edge inside
// the events that we do receive so the field is closer to correct.
function _timeBasedState(
  blockTs: BigInt,
  voteStart: BigInt,
  voteEnd: BigInt
): string {
  if (blockTs.lt(voteStart)) return "Pending";
  if (blockTs.le(voteEnd)) return "Active";
  // After voteEnd we cannot tell Succeeded vs Defeated without quorum math,
  // so leave that to the on-chain read.
  return "Active";
}

export function handleProposalCreated(event: ProposalCreated): void {
  // Use the decimal string of proposalId as the entity ID — matches how
  // the frontend casts the BigInt proposalId for on-chain lookup calls.
  let id = event.params.proposalId.toString();
  let proposal = new Proposal(id);
  proposal.proposalId = event.params.proposalId;
  proposal.proposer = event.params.proposer;
  proposal.description = event.params.description;
  proposal.voteStart = event.params.voteStart;
  proposal.voteEnd = event.params.voteEnd;
  proposal.forVotes = BigInt.fromI32(0);
  proposal.againstVotes = BigInt.fromI32(0);
  proposal.abstainVotes = BigInt.fromI32(0);
  proposal.state = _timeBasedState(
    event.block.timestamp,
    event.params.voteStart,
    event.params.voteEnd
  );
  proposal.save();
}

export function handleVoteCast(event: VoteCast): void {
  let proposalId = event.params.proposalId.toString();
  let proposal = Proposal.load(proposalId);
  if (proposal == null) return;

  // OZ support encoding: 0=Against 1=For 2=Abstain
  if (event.params.support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(event.params.weight);
  } else if (event.params.support == 1) {
    proposal.forVotes = proposal.forVotes.plus(event.params.weight);
  } else {
    proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight);
  }
  // Refresh the Pending/Active edge — a vote means we're past voteStart.
  if (proposal.state == "Pending" || proposal.state == "Active") {
    proposal.state = _timeBasedState(
      event.block.timestamp,
      proposal.voteStart,
      proposal.voteEnd
    );
  }
  proposal.save();

  let voteId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let vote = new Vote(voteId);
  vote.proposal = proposalId;
  vote.voter = event.params.voter;
  vote.support = event.params.support;
  vote.weight = event.params.weight;
  vote.reason = event.params.reason;
  vote.timestamp = event.block.timestamp;
  vote.save();
}

export function handleProposalCanceled(event: ProposalCanceled): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = "Canceled";
  proposal.save();
}

export function handleProposalQueued(event: ProposalQueued): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = "Queued";
  proposal.eta = event.params.etaSeconds;
  proposal.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.state = "Executed";
  proposal.save();
}
