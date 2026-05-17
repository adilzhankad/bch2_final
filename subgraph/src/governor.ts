import {
  ProposalCreated,
  VoteCast,
  ProposalCanceled,
  ProposalQueued,
  ProposalExecuted,
} from "../generated/DeFiGovernor/DeFiGovernor";
import { Proposal, Vote } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";

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
  proposal.state = "Pending";
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
  // Once the first vote lands the proposal is within its voting window.
  if (proposal.state == "Pending") {
    proposal.state = "Active";
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
