
:- module(knowrob_assembly,
    [
        assemblage_specified/1,
        assemblage_underspecified/1,
        assemblage_parent/2,
        assemblage_established/1,
        assemblage_connection_established/1,
        assemblage_connection_reference/3,
        assemblage_connection_transform/3,
        assemblage_destroy/1,
        assemblage_graspable_part/2,
        assemblage_possible_grasp/3,
        assemblage_possible_grasp/2,
        assemblage_fixed_part/1,
        assemblage_part/2,
        assemblage_part_links_fixtures/2,
        assemblage_part_links_part/2,
        assemblage_part_blocked_affordance/2,
        assemblage_create_connection/3
    ]).

:- use_module(library('semweb/rdf_db')).
:- use_module(library('semweb/rdfs')).
:- use_module(library('owl')).
:- use_module(library('owl_parser')).
:- use_module(library('knowrob_owl')).
:- use_module(library('knowrob_assembly')).
:- use_module(library('knowrob_planning')).

:- rdf_db:rdf_register_ns(knowrob, 'http://knowrob.org/kb/knowrob.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(knowrob_planning, 'http://knowrob.org/kb/knowrob_planning.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(knowrob_assembly, 'http://knowrob.org/kb/knowrob_assembly.owl#', [keep(true)]).

:-  rdf_meta
      assemblage_specified(r),
      assemblage_underspecified(r),
      assemblage_parent(r,r),
      assemblage_established(r),
      assemblage_connection_established(r),
      assemblage_connection_transform(r,r,t),
      assemblage_connection_reference(r,r,r),
      assemblage_destroy(r),
      assemblage_graspable_part(r,r),
      assemblage_possible_grasp(r,r,t),
      assemblage_possible_grasp(r,t),
      assemblage_fixed_part(r),
      assemblage_part(r,r),
      assemblage_part_blocked_affordance(r,r),
      assemblage_part_links_fixtures(r,t),
      assemblage_part_links_part(r,t),
      assemblage_create_connection(r,t,-).

%% assemblage_specified(+Assemblage) is det.
%
assemblage_specified(Assemblage) :-
  \+ assemblage_underspecified(Assemblage),
  forall( subassemblage(Assemblage, SubAssemblage),
          assemblage_specified(SubAssemblage) ).

%% assemblage_underspecified(+Assemblage) is det.
%
assemblage_underspecified(Assemblage) :-
  owl_unsatisfied_restriction(Assemblage, Restr),
  assemblage_relevant_restriction(Restr), !.
assemblage_underspecified(Assemblage) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Connection),
  owl_unsatisfied_restriction(Connection, Restr),
  assemblage_relevant_restriction(Restr), !.

assemblage_relevant_restriction(Restr) :-
  rdf_has(Restr, owl:'onProperty', P),
  assemblage_relevant_restriction_(P).
assemblage_relevant_restriction(Restr) :-
  rdf_has(Restr, owl:'onProperty', P),
  rdf_has(P, owl:'inverseOf', P_inv),
  assemblage_relevant_restriction_(P_inv).
assemblage_relevant_restriction_(P) :-
  rdf_equal(P, knowrob_assembly:'hasPart') ;
  rdf_equal(P, knowrob_assembly:'usesConnection') ;
  rdf_equal(P, knowrob_assembly:'consumesAffordance') ;
  rdf_equal(P, knowrob_assembly:'linksAssemblage').

%% assemblage_established(?Assemblage) is det.
%
assemblage_established(Assemblage) :-
  rdf_has(Assemblage, knowrob_assembly:'assemblageEstablished', literal(type(_,'true'))).

%% assemblage_connection_established(?Connection) is det.
%
assemblage_connection_established(Connection) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Connection), !,
  rdf_has(Assemblage, knowrob_assembly:'assemblageEstablished', literal(type(_,'true'))), !.
assemblage_connection_established(_Connection).

transform_data(TransformId, (Translation, Rotation)) :-
  % TODO: should be part of knowrob_common
  rdf_has(TransformId, knowrob:'translation', literal(type(_,Translation_atom))),
  rdf_has(TransformId, knowrob:'quaternion', literal(type(_,Rotation_atom))),
  knowrob_math:parse_vector(Translation_atom, Translation),
  knowrob_math:parse_vector(Rotation_atom, Rotation).

%% assemblage_connection_reference_object(+Connection,+TransformId,-ReferenceObj) is det.
%
assemblage_connection_reference(_Connection, TransformId, ReferenceObj) :-
  rdf_has(TransformId, knowrob:'relativeTo', ReferenceObj), !.
assemblage_connection_reference(Connection, TransformId, ReferenceObj) :-
  % FIXME: won't work when multiple instances of the reference object class are linked in the connection
  rdfs_individual_of(TransformId, Restr),
  rdfs_individual_of(Restr, owl:'Restriction'),
  rdf_has(Restr, owl:'onProperty', knowrob:'relativeTo'),
  rdf_has(Restr, owl:'onClass', ReferenceCls),
  rdf_has(Connection, knowrob_assembly:'consumesAffordance', Aff),
  rdf_has(ReferenceObj, knowrob_assembly:'hasAffordance', Aff),
  owl_individual_of(ReferenceObj,ReferenceCls), !.

%% assemblage_connection_transform(+PrimaryObject,+Connection,-Transform) is det.
%
assemblage_connection_transform(PrimaryObject, Connection, [TargetFrame,RefFrame,Translation,Rotation]) :-
  assemblage_connection_reference(Connection, TransformId, ReferenceObj),
  rdf_has(PrimaryObject, srdl2comp:'urdfName', literal(TargetFrame)),
  rdf_has(ReferenceObj , srdl2comp:'urdfName', literal(RefFrame)),
  once(owl_has(Connection, knowrob_assembly:'usesTransform', TransformId)),
  transform_data(TransformId, (Translation, Rotation)).

%% assemblage_parent(?Assemblage,?ParentAssemblage) is det.
%
assemblage_parent(Assemblage, ParentAssemblage) :-
  subassemblage(ParentAssemblage, Assemblage).

%% subassemblage(+Assemblage, ?ChildAssemblage) is det.
%
% TODO: this shows a weakness of the model, the hierarchy can be interpreted in two directions:
%             A linksAssemblage B always implies B linksAssemblage A.
%        thus I need to check on restrictions here instead of using just linksAssemblage property.
%
subassemblage(Assemblage, ChildAssemblage) :-
  ground(Assemblage), !,
  assemblage_linksAssemblage(Assemblage, ChildAssemblage),
  once((
    assemblage_linksAssemblage_restriction(Assemblage, ChildAssemblageType),
    owl_individual_of(ChildAssemblage, ChildAssemblageType))).
subassemblage(Assemblage, ChildAssemblage) :-
  ground(ChildAssemblage), !,
  assemblage_linksAssemblage(ChildAssemblage, Assemblage),
  once((
    assemblage_linksAssemblage_restriction(Assemblage, ChildAssemblageType),
    owl_individual_of(ChildAssemblage, ChildAssemblageType))).

assemblage_linksAssemblage(Assemblage, Linked) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Conn1),
  findall(X, (
    rdf_has(Conn1, knowrob_assembly:'consumesAffordance', Aff1),
    rdf_has(Part1, knowrob_assembly:'hasAffordance', Aff1),
    rdf_has(Part1, knowrob_assembly:'hasAffordance', Aff2),
    rdf_has(Conn2, knowrob_assembly:'consumesAffordance', Aff2),
    Conn1 \= Conn2,
    rdf_has(X, knowrob_assembly:'usesConnection', Conn2)
  ), Links),
  list_to_set(Links, Links_set),
  member(Linked, Links_set).

assemblage_linksAssemblage_restriction(Assemblage, ChildAssemblageType) :-
  rdfs_individual_of(Assemblage, Restr),
  rdfs_individual_of(Restr, owl:'Restriction'),
  rdf_has(Restr, owl:'onProperty', knowrob_assembly:'usesConnection'),
  owl_restriction(Restr, restriction(_, cardinality(_,_,Descr))),
  owl_description(Descr, Descr_x),
  ( Descr_x = restriction('http://knowrob.org/kb/knowrob_assembly.owl#linksAssemblage', some_values_from(ChildAssemblageType)) ; (
    Descr_x = intersection_of(List),
    member(restriction('http://knowrob.org/kb/knowrob_assembly.owl#linksAssemblage', some_values_from(ChildAssemblageType)), List)
  )).

%% assemblage_graspable_part(+Assemblage,+Part) is det.
%
assemblage_graspable_part(Assemblage, Part) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Conn),
  assemblage_part(Assemblage, Part),
  assemblage_possible_grasp(Part, Conn, _).

%% assemblage_possible_grasp(+Assemblage, -(GraspObj,GraspAff,GraspSpec)) is det.
%% assemblage_possible_grasp(+Object, +TargetConnection, -(GraspObj,GraspAff,GraspSpec)) is det.
%
assemblage_possible_grasp(Assemblage, PossibleGrasp) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', TargetConnection),
  assemblage_part(Assemblage, Part),
  assemblage_possible_grasp(Part, TargetConnection, PossibleGrasp).
assemblage_possible_grasp(Object, TargetConnection, (GraspObj,GraspAff,GraspSpec)) :-
  (GraspObj=Object ; assemblage_part_links_part(Object, GraspObj)),
  rdf_has(GraspObj, knowrob_assembly:'hasAffordance', GraspAff),
  rdfs_individual_of(GraspAff, knowrob_assembly:'GraspingAffordance'),
  % ensure grasped affordance not used in (not yet established) target assemblage
  \+ rdf_has(TargetConnection, knowrob_assembly:'consumesAffordance', GraspAff),
  % ensure the affordance is not yet blocked
  \+ assemblage_part_blocked_affordance(GraspObj, GraspAff),
  % find the grasp specification
  owl_has(GraspAff, knowrob_assembly:'graspAt', GraspSpec),
  % TODO: also ensure that grasp does not indirectly block affordances required by TargetConnection
  true.

%% assemblage_create_connection(+ConnType,+Objects,-ConnId) is det.
%
assemblage_create_connection(ConnType, Objects, ConnId) :-
  rdf_instance_from_class(ConnType, ConnId),
  forall((
    rdfs_subclass_of(ConnType,Restr),
    rdfs_individual_of(Restr,owl:'Restriction'),
    rdf_has(Restr, owl:onProperty, knowrob_assembly:'consumesAffordance'),
    rdf_has(Restr, owl:'onClass', AffType)),once((
      member(Obj,Objects),
      rdf_has(Obj, knowrob_assembly:'hasAffordance', Affordance),
      rdfs_individual_of(Affordance, AffType),
      rdf_assert(ConnId, knowrob_assembly:'consumesAffordance', Affordance)
    ))).

%% assemblage_fixed_part(+FixedPart) is det.
%
assemblage_fixed_part(FixedPart) :-
  rdfs_individual_of(FixedPart, knowrob_assembly:'FixedPart').

%% assemblage_part(?Assemblage,?AtomicPart) is det.
%
assemblage_part(Assemblage, AtomicPart) :-
  ground(AtomicPart), !,
  rdf_has(AtomicPart, knowrob_assembly:'hasAffordance', Affordance),
  rdf_has(Conn, knowrob_assembly:'consumesAffordance', Affordance),
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Conn).
assemblage_part(Assemblage, AtomicPart) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Conn),
  rdf_has(Conn, knowrob_assembly:'consumesAffordance', Affordance),
  rdf_has(AtomicPart, knowrob_assembly:'hasAffordance', Affordance).

%% assemblage_part_blocked_affordance(?Assemblage,?AtomicPart) is det.
%
assemblage_part_blocked_affordance(Part, Affordance) :-
  rdf_has(Part, knowrob_assembly:'hasAffordance', Affordance),
  once((
    rdf_has(Connection, knowrob_assembly:'blocksAffordance', Affordance),
    % if blocked by assemblage then assemblage must be established to block affordance
    (  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Connection)
    -> assemblage_established(Assemblage) ; true )
  )).

%% assemblage_destroy(+Connection) is det.
%% assemblage_destroy(+Assemblage) is det.
%
assemblage_destroy(Connection) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Connection), !,
  assemblage_destroy(Assemblage).
assemblage_destroy(Assemblage) :-
  rdf_has(Assemblage, knowrob_assembly:'usesConnection', Connection),
  rdf_retractall(Assemblage,_,_),
  rdf_retractall(Connection,_,_).

%% assemblage_part_links_fixtures(+Part) is det.
%
assemblage_part_links_fixtures(Part, Parts) :-
  assemblage_part_links_assemblages(Part, Assemblages),
  findall(X, (
    member(Assemblage, Assemblages),
    assemblage_part(Assemblage,X),
    assemblage_fixed_part(X)
  ), Parts_list),
  list_to_set(Parts_list, Parts).

%% assemblage_part_links_part(+Part, ?OtherPart) is det.
%
assemblage_part_links_part(Part, OtherPart) :-
  assemblage_part_links_assemblages(Part, Assemblages),
  findall(X, (
    member(Assemblage, Assemblages),
    assemblage_part(Assemblage,X)
  ), Parts_list),
  list_to_set(Parts_list, Parts),
  member(OtherPart, Parts),
  OtherPart \= Part.

assemblage_part_links_assemblages(Part, Assemblages) :-
  assemblage_part_links_assemblages(Part, [], Assemblages_list),
  list_to_set(Assemblages_list, Assemblages).
assemblage_part_links_assemblages(Part, Blacklist, LinkedAssemblages) :-
  % find all assemblages with connections consuming an affordance of the part
  findall(Direct_assemblage, (
    assemblage_part(Direct_assemblage, Part),
    assemblage_established(Direct_assemblage),
    \+ member(Direct_assemblage,Blacklist)
  ), LinkedAssemblages_direct),
  append(Blacklist, LinkedAssemblages_direct, NewBlacklist),
  % find all other parts used in linked assemablages
  findall(Direct_part, (
    member(Direct_assemblage,LinkedAssemblages_direct),
    assemblage_part(Direct_assemblage, Direct_part),
    Direct_part \= Part
  ), LinkedParts_list),
  list_to_set(LinkedParts_list, LinkedParts),
  % recursively find linked assemblages for linked parts
  findall(LinkedAssemblages_sibling, (
    member(Direct_part,LinkedParts),
    assemblage_part_links_assemblages(Direct_part,NewBlacklist,LinkedAssemblages_sibling)
  ), LinkedAssemblages_indirect),
  flatten([LinkedAssemblages_direct|LinkedAssemblages_indirect], LinkedAssemblages).
