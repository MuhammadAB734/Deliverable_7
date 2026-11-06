DELIMITER $$
CREATE PROCEDURE migrate_d2_v1_to_v2()
BEGIN
    IF EXISTS (
        SELECT 1
        FROM contributions co
        JOIN cycles cy ON cy.cycle_id = co.cycle_id
        JOIN circles ci ON ci.circle_id = cy.circle_id
        JOIN memberships ms ON ms.membership_id = co.membership_id
        WHERE co.amount <> ci.contribution_amount
           OR ms.circle_id <> cy.circle_id
    ) THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'Migration stopped: contribution amount or circle consistency audit failed';
    END IF;
END$$
DELIMITER ;

CALL migrate_d2_v1_to_v2();
DROP PROCEDURE migrate_d2_v1_to_v2;

DROP TRIGGER IF EXISTS trg_validate_contribution_insert;
DROP TRIGGER IF EXISTS trg_validate_contribution_update;

CREATE INDEX idx_memberships_member_status
    ON memberships(member_id, status);
CREATE INDEX idx_contributions_cycle_status
    ON contributions(cycle_id, payment_status);
CREATE INDEX idx_contributions_membership_date
    ON contributions(membership_id, contribution_date);
CREATE INDEX idx_payouts_membership
    ON payouts(membership_id);

ALTER TABLE contributions DROP COLUMN amount;

CREATE OR REPLACE VIEW contribution_details AS
SELECT co.contribution_id,
       ci.contribution_amount AS amount,
       co.contribution_date,
       co.payment_status,
       co.cycle_id,
       co.membership_id
FROM contributions co
JOIN cycles cy ON cy.cycle_id = co.cycle_id
JOIN circles ci ON ci.circle_id = cy.circle_id;